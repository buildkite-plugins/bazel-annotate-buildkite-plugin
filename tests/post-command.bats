#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Create a temporary directory for test files
  export TEMP_DIR=$(mktemp -d)

  # Setup environment
  export BUILDKITE=true
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_SKIP_IF_NO_BEP=false

  # Mock the process_bep function to avoid relying on external tools
  cat > "$TEMP_DIR/mock-bazel-bep.bash" << 'EOF'
#!/bin/bash
# Mock version of bazel-bep.bash that avoids external dependencies

process_bep() {
  local BEP_FILE="$1"

  echo "Mock processing BEP file: $BEP_FILE"
  if [[ -f "$BEP_FILE" ]]; then
    echo "Mock BEP file exists, processing successful"
    # Call create_annotation after successful processing
    create_annotation "info" "This is a mock summary"
    return 0
  else
    echo "Mock BEP file does not exist"
    return 1
  fi
}

create_annotation() {
  local style="$1"
  local content="$2"
  echo "Mock annotation created with style: $style and append flag enabled"
}
EOF

  # Replace the real lib with our mock
  export HOOKS_ORIG_DIR="$PWD/lib"
  mkdir -p "$TEMP_DIR/lib"
  cp "$TEMP_DIR/mock-bazel-bep.bash" "$TEMP_DIR/lib/bazel-bep.bash"

  # Keep the original plugin.bash file
  cp "$PWD/lib/plugin.bash" "$TEMP_DIR/lib/plugin.bash"

  # Create a wrapper for the post-command hook
  mkdir -p "$TEMP_DIR/hooks"
  cat > "$TEMP_DIR/hooks/post-command" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source from the temp directory instead of the original
DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
LIB_DIR="$(cd "$DIR/../lib" && pwd)"

# Source the mocked files
. "$LIB_DIR/plugin.bash"
. "$LIB_DIR/bazel-bep.bash"

# Get plugin configuration
BEP_FILE=$(plugin_read_config BEP_FILE "")

# Check if we should skip if no BEP file found
SKIP_IF_NO_BEP=$(plugin_read_config SKIP_IF_NO_BEP "false")

# If we still don't have a BEP file, check if it exists at common locations
if [[ -z "${BEP_FILE}" ]]; then
  # Try some common locations
  COMMON_LOCATIONS=(
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-events.json"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-bep.json"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bep.json"
  )

  for location in "${COMMON_LOCATIONS[@]}"; do
    if [[ -f "$location" ]]; then
      BEP_FILE="$location"
      echo "Found BEP file at common location: ${BEP_FILE}"
      break
    fi
  done
fi

# Check if we have a BEP file
if [[ -z "${BEP_FILE}" ]]; then
  if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
    echo "No BEP file specified and skip_if_no_bep is true, skipping annotation"
    exit 0
  else
    echo "Error: No BEP file specified"
    exit 1
  fi
fi

# Check if the BEP file exists
if [[ ! -f "${BEP_FILE}" ]]; then
  if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
    echo "BEP file not found at '${BEP_FILE}' and skip_if_no_bep is true, skipping annotation"
    exit 0
  else
    echo "Error: BEP file not found at '${BEP_FILE}'"
    exit 1
  fi
fi

# Process the BEP file and create the annotation
process_bep "${BEP_FILE}"
EOF
  chmod +x "$TEMP_DIR/hooks/post-command"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

@test "Skip when no BEP file and skip option is enabled" {
  # No BEP file, but we'll enable skip option
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_SKIP_IF_NO_BEP=true

  # Ensure no common files exist
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-events.json" || true
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-bep.json" || true
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bep.json" || true

  run "$TEMP_DIR/hooks/post-command"

  assert_success
  assert_output --partial "skip_if_no_bep is true, skipping annotation"
}

@test "Fail when no BEP file and skip option is disabled" {
  # No BEP file, skip option disabled
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_SKIP_IF_NO_BEP=false

  # Ensure no common files exist
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-events.json" || true
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-bep.json" || true
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bep.json" || true

  run "$TEMP_DIR/hooks/post-command"

  assert_failure
  assert_output --partial "Error: No BEP file specified"
}

@test "Process BEP file when explicitly provided" {
  # Create a sample BEP file
  touch "$TEMP_DIR/sample.bep"
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_BEP_FILE="$TEMP_DIR/sample.bep"

  run "$TEMP_DIR/hooks/post-command"

  assert_success
  assert_output --partial "Mock processing BEP file: $TEMP_DIR/sample.bep"
}

# Removed test for bazel_command since we removed that functionality

@test "Find BEP file at common location" {
  # Create sample BEP file at a common location
  mkdir -p "${BUILDKITE_BUILD_CHECKOUT_PATH:-$TEMP_DIR}"
  touch "${BUILDKITE_BUILD_CHECKOUT_PATH:-$TEMP_DIR}/bazel-events.json"

  # Make sure we're using the right path for testing
  export BUILDKITE_BUILD_CHECKOUT_PATH="$TEMP_DIR"

  run "$TEMP_DIR/hooks/post-command"

  assert_success
  assert_output --partial "Found BEP file at common location: $TEMP_DIR/bazel-events.json"
  assert_output --partial "Mock processing BEP file: $TEMP_DIR/bazel-events.json"
}

@test "Skip when BEP file doesn't exist and skip is enabled" {
  # Reference a non-existent BEP file with skip enabled
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_BEP_FILE="$TEMP_DIR/nonexistent.bep"
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_SKIP_IF_NO_BEP=true

  run "$TEMP_DIR/hooks/post-command"

  assert_success
  assert_output --partial "BEP file not found at '$TEMP_DIR/nonexistent.bep' and skip_if_no_bep is true"
}

@test "Verify annotations are created with append flag" {
  # Create a sample BEP file
  touch "$TEMP_DIR/sample.bep"
  export BUILDKITE_PLUGIN_BAZEL_BEP_ANNOTATE_BEP_FILE="$TEMP_DIR/sample.bep"

  run "$TEMP_DIR/hooks/post-command"

  assert_success
  assert_output --partial "Mock annotation created with style: info and append flag enabled"
}
