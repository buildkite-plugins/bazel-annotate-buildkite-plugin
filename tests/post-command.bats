#!/usr/bin/env bats

# Tests for Bazel BEP Failure Analyzer plugin

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"
  
  # Create a temporary directory for test files
  export TEMP_DIR=$(mktemp -d)
  
  # Setup environment
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_SKIP_IF_NO_BEP=false
  
  # Keep the original plugin.bash file
  mkdir -p "$TEMP_DIR/lib"
  cp "$PWD/lib/plugin.bash" "$TEMP_DIR/lib/plugin.bash"
  
  # Create mock analyzer binary
  mkdir -p "$TEMP_DIR/bin"
  cat > "$TEMP_DIR/bin/bazel_failure_analyzer" << 'EOF'
#!/bin/bash
# Mock analyzer binary for testing

if [[ "$1" == "--help" ]]; then
  echo "Usage: bazel_failure_analyzer BEP_FILE [options]"
  exit 0
fi

BEP_FILE="$1"
shift

# Parse arguments
VERBOSE=false
SKIP_IF_NO_FAILURES=false
OUTPUT_FORMAT="buildkite"

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --skip-if-no-failures)
      SKIP_IF_NO_FAILURES=true
      shift
      ;;
    --output-format=*)
      OUTPUT_FORMAT="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Mock behavior based on file content
if [[ ! -f "$BEP_FILE" ]]; then
  echo "Error: BEP file not found: $BEP_FILE"
  exit 1
fi

# Check if file contains failure indicators
if grep -q "failure\|error\|failed" "$BEP_FILE" 2>/dev/null; then
  echo "Mock: Found failures in $BEP_FILE"
  if [[ "$OUTPUT_FORMAT" == "buildkite" ]]; then
    echo "Mock Buildkite annotation created"
  fi
  exit 1
else
  if [[ "$VERBOSE" == "true" ]]; then
    echo "Mock: No failures found in $BEP_FILE"
  fi
  if [[ "$SKIP_IF_NO_FAILURES" == "true" ]]; then
    exit 0
  else
    echo "Mock: Build completed successfully"
    exit 0
  fi
fi
EOF
  chmod +x "$TEMP_DIR/bin/bazel_failure_analyzer"
  
  # Create wrapper for the post-command hook
  mkdir -p "$TEMP_DIR/hooks"
  cat > "$TEMP_DIR/hooks/post-command" << 'EOF'
#!/bin/bash
set -euo pipefail

DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
LIB_DIR="$(cd "$DIR/../lib" && pwd)"

# Source the plugin configuration
. "$LIB_DIR/plugin.bash"

# Get plugin configuration
BEP_FILE=$(plugin_read_config BEP_FILE "")
SKIP_IF_NO_BEP=$(plugin_read_config SKIP_IF_NO_BEP "false")
VERBOSE=$(plugin_read_config VERBOSE "false")

echo "Bazel Failure Analyzer - Looking for BEP protobuf file..."

# If no BEP file specified, look for common protobuf locations
if [[ -z "${BEP_FILE}" ]]; then
  COMMON_LOCATIONS=(
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-events.pb"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bazel-bep.pb"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/bep.pb"
    "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}/events.pb"
  )

  for location in "${COMMON_LOCATIONS[@]}"; do
    if [[ -f "$location" ]]; then
      BEP_FILE="$location"
      echo "Found BEP protobuf file: ${BEP_FILE}"
      break
    fi
  done
fi

# Check if we have a BEP file
if [[ -z "${BEP_FILE}" ]]; then
  if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
    echo "No BEP protobuf file found, skipping (skip_if_no_bep=true)"
    exit 0
  else
    echo "Error: No BEP protobuf file found"
    exit 1
  fi
fi

# Check if the BEP file exists
if [[ ! -f "${BEP_FILE}" ]]; then
  if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
    echo "BEP file not found at '${BEP_FILE}', skipping (skip_if_no_bep=true)"
    exit 0
  else
    echo "Error: BEP file not found at '${BEP_FILE}'"
    exit 1
  fi
fi

# Use the analyzer binary
ANALYZER_BINARY="$DIR/../bin/bazel_failure_analyzer"
if [[ ! -f "$ANALYZER_BINARY" ]]; then
  echo "Error: Analyzer binary not found at: $ANALYZER_BINARY"
  exit 1
fi

# Run the analyzer
echo "Analyzing BEP file for failures..."
ANALYZER_ARGS=("$BEP_FILE" "--output-format=buildkite")

if [[ "${VERBOSE}" == "true" ]]; then
  ANALYZER_ARGS+=("--verbose")
fi

if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
  ANALYZER_ARGS+=("--skip-if-no-failures")
fi

"$ANALYZER_BINARY" "${ANALYZER_ARGS[@]}" || {
  status=$?
  echo "Warning: Analyzer returned non-zero status ($status)"
  if [[ "${SKIP_IF_NO_BEP}" == "true" ]]; then
    echo "Ignoring error due to skip_if_no_bep=true"
    exit 0
  else
    exit $status
  fi
}

echo "BEP analysis complete"
EOF
  chmod +x "$TEMP_DIR/hooks/post-command"
}

teardown() {
  rm -rf "$TEMP_DIR"
}

@test "Skip when no BEP file and skip_if_no_bep is true" {
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_SKIP_IF_NO_BEP=true
  
  # Ensure no protobuf files exist
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}"/*.pb || true
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_success
  assert_output --partial "skip_if_no_bep=true"
}

@test "Fail when no BEP file and skip_if_no_bep is false" {
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_SKIP_IF_NO_BEP=false
  
  # Ensure no protobuf files exist
  rm -f "${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}"/*.pb || true
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_failure
  assert_output --partial "Error: No BEP protobuf file found"
}

@test "Process BEP file when explicitly provided" {
  # Create a sample BEP file with failure content
  echo "build failed with error" > "$TEMP_DIR/sample.pb"
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_BEP_FILE="$TEMP_DIR/sample.pb"
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_failure
  assert_output --partial "Found failures in $TEMP_DIR/sample.pb"
}

@test "Find BEP file at common location" {
  # Create sample BEP file at a common location
  mkdir -p "${BUILDKITE_BUILD_CHECKOUT_PATH:-$TEMP_DIR}"
  echo "build succeeded" > "${BUILDKITE_BUILD_CHECKOUT_PATH:-$TEMP_DIR}/events.pb"
  
  export BUILDKITE_BUILD_CHECKOUT_PATH="$TEMP_DIR"
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_success
  assert_output --partial "Found BEP protobuf file: $TEMP_DIR/events.pb"
}

@test "Handle verbose option" {
  echo "build succeeded" > "$TEMP_DIR/test.pb"
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_BEP_FILE="$TEMP_DIR/test.pb"
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_VERBOSE=true
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_success
  assert_output --partial "No failures found"
}

@test "Handle missing analyzer binary" {
  echo "build succeeded" > "$TEMP_DIR/test.pb"
  export BUILDKITE_PLUGIN_BAZEL_ANNOTATE_BEP_FILE="$TEMP_DIR/test.pb"
  
  # Remove the mock analyzer binary
  rm "$TEMP_DIR/bin/bazel_failure_analyzer"
  
  run "$TEMP_DIR/hooks/post-command"
  
  assert_failure
  assert_output --partial "Analyzer binary not found"
}
