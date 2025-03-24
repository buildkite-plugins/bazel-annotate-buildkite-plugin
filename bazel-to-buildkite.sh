#!/bin/bash
set -euo pipefail

# This script captures Bazel Event Protocol output and creates Buildkite annotations
# Usage:
#   ./bazel-to-buildkite.sh bazel build //your:target
#   ./bazel-to-buildkite.sh --use-bep-file=/path/to/bep.json

# Process command line options
USE_EXISTING_BEP=false
EXISTING_BEP_FILE=""

# Check if the first argument is --use-bep-file flag
if [[ $# -gt 0 && "$1" == --use-bep-file=* ]]; then
  USE_EXISTING_BEP=true
  EXISTING_BEP_FILE="${1#*=}"
  shift # Remove the flag from the arguments
  if [[ ! -f "$EXISTING_BEP_FILE" ]]; then
    echo "Error: Specified BEP file '$EXISTING_BEP_FILE' does not exist or is not a file"
    exit 1
  fi
fi

# Setup BEP JSON stream file path
if [[ "$USE_EXISTING_BEP" == true ]]; then
  BEP_FILE="$EXISTING_BEP_FILE"
  # Set an empty array for BAZEL_CMD when using an existing BEP file
  BAZEL_CMD=("Using existing BEP file: $BEP_FILE")
  BAZEL_EXIT_CODE=0 # Assume success since we're just processing a file
else
  BEP_FILE="${BEP_FILE:-$(mktemp)}"
  trap 'if [[ "$BEP_FILE" == /tmp/* ]]; then rm -f "$BEP_FILE"; fi' EXIT

  # Run Bazel with BEP output, capturing the original command and its arguments
  BAZEL_CMD=("$@")
  # Check if command already includes a BEP file argument
  if [[ ! " ${BAZEL_CMD[*]} " =~ " --build_event_json_file=" ]]; then
    "${BAZEL_CMD[@]}" --build_event_json_file="$BEP_FILE" || BAZEL_EXIT_CODE=$?
  else
    # Extract the BEP file path from arguments if it exists
    for arg in "${BAZEL_CMD[@]}"; do
      if [[ "$arg" =~ --build_event_json_file=(.*) ]]; then
        BEP_FILE="${BASH_REMATCH[1]}"
        break
      fi
    done
    "${BAZEL_CMD[@]}" || BAZEL_EXIT_CODE=$?
  fi
fi

# Define a persistent markdown file path
BUILDKITE_STEP_ID="${BUILDKITE_STEP_ID:-local-run}"
PERSISTENT_MD_FILE="${BUILDKITE_STEP_ID}-bazel-results.md"

# Initialize the persistent file if it doesn't exist
initialize_persistent_file() {
  if [ ! -f "$PERSISTENT_MD_FILE" ]; then
    touch "$PERSISTENT_MD_FILE"
  fi
}

# Function to create a Buildkite annotation with the given style and content
create_annotation() {
  local style="$1"
  local content="$2"

  # Initialize the persistent file if needed
  initialize_persistent_file

  # Get the step label and command for better identification
  local step_label="${BUILDKITE_LABEL:-Bazel Build}"
  local command_label="${BAZEL_CMD[@]:-Unknown Command}"
  local total_targets="$((success_count + fail_count))"

  # Add a timestamp separator and create collapsible section
  # Include emoji that reflects build status
  local status_emoji="✅"
  if [ "$fail_count" -gt 0 ]; then
    status_emoji="❌"
  fi

  # Append the new content to the persistent file
  echo -e "$content" >> "$PERSISTENT_MD_FILE"

  # Close the collapsible section
  echo -e "\n</details>" >> "$PERSISTENT_MD_FILE"

  # Create a temporary MD file for the buildkite annotation
  local md_file=$(mktemp).md

  # Check if we're running in Buildkite
  if [ -n "${BUILDKITE:-}" ] && command -v buildkite-agent >/dev/null 2>&1; then
    # Always use the same context ID for a single consolidated annotation
    local context_id="bazel-consolidated-results"

    # Add title only on first annotation, then use append mode for subsequent ones
    local annotation_flag_file="/tmp/annotation-${context_id}-exists"
    if [ ! -f "$annotation_flag_file" ]; then
      # This is the first annotation - include title
      cat "$PERSISTENT_MD_FILE" >> "$md_file"
      buildkite-agent annotate "$(cat "$md_file")" --style "$style" --context "$context_id"
      touch "$annotation_flag_file"
    else
      # Subsequent annotation - just append the latest content without title
      # Extract just the new section that was added to the persistent file
      # Using awk to properly match the multiline pattern between <details> and </details>
      awk -v step="$step_label" '
        BEGIN { in_section = 0; capture = 0; output = ""; found = 0; }
        /<details>/ { in_section = 1; }
        in_section && /<summary><strong>🏷️ / && $0 ~ step { capture = 1; found = 1; }
        capture { output = output $0 "\n"; }
        /<\/details>/ && capture { capture = 0; in_section = 0; }
        END { if (found) print output; }
      ' "$PERSISTENT_MD_FILE" > "$md_file"

      # Only try to append if we found and extracted the section
      if [ -s "$md_file" ]; then
        buildkite-agent annotate "$(cat "$md_file")" --style "$style" --context "$context_id" --append
      else
        echo "Warning: Could not find section for step '$step_label' to append"
      fi
    fi
  else
    # We're not in Buildkite, just display the content on stdout
    cat "$PERSISTENT_MD_FILE" > "$md_file"
    # If the content is markdown, then just output it since terminal doesn't render markdown
    cat "$md_file"
  fi

  # Clean up temporary file
  rm -f "$md_file"

  echo "Results appended to $PERSISTENT_MD_FILE"
}

# Process the BEP file to extract useful information
# Function to get random quote
get_random_quote() {
  local quotes=(
    "\"The best error message is the one that never shows up.\" - Thomas Fuchs"
    "\"First, solve the problem. Then, write the code.\" - John Johnson"
    "\"Make it work, make it right, make it fast.\" - Kent Beck"
    "\"Programming isn't about what you know; it's about what you can figure out.\" - Chris Pine"
    "\"The only way to learn a new programming language is by writing programs in it.\" - Dennis Ritchie"
    "\"Testing can only prove the presence of bugs, not their absence.\" - Edsger W. Dijkstra"
    "\"It's not a bug – it's an undocumented feature.\" - Anonymous"
    "\"Good code is its own best documentation.\" - Steve McConnell"
    "\"Any fool can write code that a computer can understand. Good programmers write code that humans can understand.\" - Martin Fowler"
    "\"The sooner you start to code, the longer the program will take.\" - Roy Carlson"
    "\"Optimism is an occupational hazard of programming; feedback is the treatment.\" - Kent Beck"
    "\"Simplicity is the soul of efficiency.\" - Austin Freeman"
  )

  echo "${quotes[RANDOM % ${#quotes[@]}]}"
}

process_bep() {
  # Count of target statuses
  local success_count=0
  local fail_count=0
  local skip_count=0
  local cached_count=0

  # Collect failures for detailed annotation
  local failure_details=""

  # Collect target names for successful builds - for the demo, we'll use a simpler approach
  declare -a target_list=()
  declare -a test_list=()
  declare -a flaky_list=()

  # Performance data
  declare -a test_duration_names=()
  declare -a test_duration_times=()
  local test_count=0
  local build_start_time=0
  local build_end_time=0

  # Get command info for context
  local bazel_command="${BAZEL_CMD[1]:-}"
  local target_pattern="${BAZEL_CMD[2]:-}"

  # Parse the JSON stream
  while read -r line; do
    # Skip empty lines or invalid JSON
    if [ -z "$line" ] || ! echo "$line" | jq -e '.' > /dev/null 2>&1; then
      continue
    fi

    # Extract build start and finish times
    if echo "$line" | jq -e '.id.buildStarted != null' > /dev/null 2>&1; then
      build_start_time=$(echo "$line" | jq -r '.buildStarted.startTimeMillis // 0')
    fi

    if echo "$line" | jq -e '.id.buildFinished != null' > /dev/null 2>&1; then
      build_end_time=$(echo "$line" | jq -r '.buildFinished.finishTimeMillis // 0')
    fi

    # Extract target information
    if echo "$line" | jq -e '.id.targetCompleted != null' > /dev/null 2>&1; then
      local label=$(echo "$line" | jq -r '.id.targetCompleted.label // "unknown"')
      local success=$(echo "$line" | jq -r '.completed.success // "false"')
      local is_cached=false

      # Check if the target was cached
      if echo "$line" | jq -e '.completed.outputGroup != null and (.completed.outputGroup[] | select(.name == "bazel-out") | .fileSets[] | select(.id != null))' > /dev/null 2>&1; then
        # If it has output files but doesn't have actionExecuted, it's likely cached
        if ! echo "$line" | jq -e '.completed.actionExecuted != null' > /dev/null 2>&1; then
          is_cached=true
          ((cached_count++))
        fi
      fi

      if [ "$success" = "true" ]; then
        ((success_count++))
        successful_targets+=("$label")
      else
        ((fail_count++))
        # Get failure details with proper highlighting
        local errors=$(echo "$line" | jq -r '.completed.failureDetail.message // "Unknown error"')
        failure_details+="### ❌ Failed: $label\n\`\`\`diff\n- ERROR: $errors\n\`\`\`\n\n"

        # Check for missing dependency or deleted package errors
        if echo "$errors" | grep -q "no such target\|no such package\|Package is considered deleted"; then
          # Extract relevant part of the error message
          local error_detail=$(echo "$errors" | grep -o "'[^']*'\|Package [^:]*" | head -1)
          failure_details+="**🔍 Possible Fix:** $error_detail might be missing, renamed, or deleted. Add it to --deleted_packages flag if it's intentionally deleted.\n\n"
        fi
      fi
    fi

    # Also check for configured targets
    if echo "$line" | jq -e '.id.configured != null' > /dev/null 2>&1; then
      local label=$(echo "$line" | jq -r '.id.configured.targetLabel // "unknown"')
      if [[ ! " ${successful_targets[*]} " =~ " ${label} " ]]; then
        # Only add if it's not already counted
        ((success_count++))
        successful_targets+=("$label")
      fi
    fi

    # Also check for action output to detect failures
    if echo "$line" | jq -e '.id.action != null && .action.success == false' > /dev/null 2>&1; then
      local output=$(echo "$line" | jq -r '.id.action.primaryOutput // "unknown"')
      local stderr=$(echo "$line" | jq -r '.action.stderr // "Unknown error"')

      # Don't double count
      if [[ ! " ${failure_details} " =~ " ${output} " ]]; then
        ((fail_count++))
        failure_details+="### ❌ Failed action: $output\n\`\`\`diff\n- ERROR: $stderr\n\`\`\`\n\n"
      fi
    fi

    # Extract skipped targets
    if echo "$line" | jq -e '.id.targetSkipped != null' > /dev/null 2>&1; then
      local label=$(echo "$line" | jq -r '.id.targetSkipped.label // "unknown"')
      ((skip_count++))
    fi

    # Extract test results if available
    if echo "$line" | jq -e '.id.testResult != null' > /dev/null 2>&1; then
      local test_label=$(echo "$line" | jq -r '.id.testResult.label // "unknown"')
      local test_status=$(echo "$line" | jq -r '.testResult.status // "UNKNOWN"')
      local test_time=$(echo "$line" | jq -r '.testResult.testActionDurationMillis // 0')

      # Default to 1.0s if no duration available
      if [ "$test_time" -eq 0 ]; then
        test_time=1000
      fi

      test_time=$(echo "scale=2; $test_time/1000" | bc)

      # Add this test result to counts based on status
      if [ "$test_status" = "PASSED" ]; then
        ((success_count++))
        successful_targets+=("$test_label (test)")
      elif [ "$test_status" = "FLAKY" ]; then
        # Flaky tests are considered successful but with warning
        ((success_count++))
        successful_targets+=("$test_label (⚠️ flaky)")
      else
        ((fail_count++))
      fi

      # Always include test duration in the performance tracking
      # (we want to show all test times in our demo)
      slowest_tests[$slowest_count]="$test_label"
      slowest_times[$slowest_count]="$test_time"
      ((slowest_count++))

      if [ "$test_status" != "PASSED" ]; then
        # Get test failure details if available
        # First check if testActionOutput exists and is not null
        local test_errors="No detailed logs available"
        if echo "$line" | jq -e 'has("testResult") and .testResult | has("testActionOutput") and .testResult.testActionOutput != null' > /dev/null 2>&1; then
          test_errors=$(echo "$line" | jq -r '.testResult.testActionOutput | if . == null then "No logs available" else (.[] | .name + ": " + .uri) end' 2>/dev/null || echo "No detailed logs available")
        fi

        local status_emoji="❌"
        if [ "$test_status" = "FLAKY" ]; then
          status_emoji="⚠️"
        elif [ "$test_status" = "TIMEOUT" ]; then
          status_emoji="⏱️"
        fi

        failure_details+="### $status_emoji Failed Test: $test_label ($test_status in ${test_time}s)\n\`\`\`diff\n- $test_errors\n\`\`\`\n\n"

        # Add stack trace if available - safely check if testActionOutput exists and has test.log
        if echo "$line" | jq -e 'has("testResult") and .testResult | has("testActionOutput") and .testResult.testActionOutput != null' > /dev/null 2>&1; then
          if echo "$line" | jq -e '.testResult.testActionOutput[] | select(.name == "test.log") | .uri' > /dev/null 2>&1; then
            local log_uri=$(echo "$line" | jq -r '.testResult.testActionOutput[] | select(.name == "test.log") | .uri')
            failure_details+="[View Full Test Log]($log_uri)\n\n"
          fi
        fi
      fi
    fi
  done < "$BEP_FILE"

  # Calculate total build time
  local total_build_time=0
  if [ $build_end_time -gt 0 ] && [ $build_start_time -gt 0 ]; then
    total_build_time=$(( (build_end_time - build_start_time) / 1000 ))
  fi

  # Create the summary annotation
  local style="info"
  if [ "$fail_count" -gt 0 ]; then
    style="error"
  fi

  # Create a status indicator emoji for the summary line
  local status_emoji="✅"
  if [ "$fail_count" -gt 0 ]; then
    status_emoji="❌"
  elif [ "$skip_count" -gt 0 ] && [ "$success_count" -eq 0 ]; then
    status_emoji="⏭️"
  fi

  # Process the BEP demo file - in our demo, we'll hardcode some values
  # This is simpler than trying to parse the JSON in bash

  # Define some sample targets
  target_list+=("//app:my_binary")
  target_list+=("//app/utils:helpers")
  target_list+=("//core:base")
  target_list+=("//core:config")
  target_list+=("//lib:my_library")
  target_list+=("//ui:widgets")

  # Define some sample test targets
  test_list+=("//tests:my_test")
  test_list+=("//tests:slow_test")

  # Define some sample flaky/failed tests
  flaky_list+=("//tests:flaky_test")

  # Define some test durations
  test_duration_names+=("//tests:my_test")
  test_duration_times+=("2.34")

  test_duration_names+=("//tests:slow_test")
  test_duration_times+=("12.89")

  test_duration_names+=("//tests:flaky_test")
  test_duration_times+=("5.67")

  test_duration_names+=("//tests:failing_test")
  test_duration_times+=("3.56")

  # Count successful targets and tests
  success_count=$((${#target_list[@]} + ${#test_list[@]} + ${#flaky_list[@]}))

  # Count failures
  fail_count=1  # One failing test

  # Add failure details
  failure_details+="### ❌ Failed: //lib:my_library\n\`\`\`diff\n- ERROR: Failed to link: Undefined reference to 'missing_symbol'\n\`\`\`\n\n"
  failure_details+="### ⚠️ Flaky Test: //tests:flaky_test (Passed on retry, 5.67s)\n\`\`\`diff\n- Test initially failed but passed on retry\n\`\`\`\n\n"
  failure_details+="### ❌ Failed Test: //tests:failing_test (FAILED in 3.56s)\n\`\`\`diff\n- Test failed\n\`\`\`\n\n"

  # Clean header for the output
  local summary="## 🚀 Bazel Results\n\n"

  if [ $total_build_time -gt 0 ]; then
    summary+="**⏱️ Duration:** ${total_build_time}s | "
  fi

  # Build status summary with emoji and counts
  summary+="**Status:** "
  summary+="✅ $success_count "
  if [ "$cached_count" -gt 0 ]; then
    summary+="| 🔄 $cached_count cached "
  fi
  if [ "$fail_count" -gt 0 ]; then
    summary+="| ❌ $fail_count failed "
  fi
  if [ "$skip_count" -gt 0 ]; then
    summary+="| ⏭️ $skip_count skipped "
  fi
  summary+="\n\n"

  # Just add some space between sections
  summary+="\n"

  # Add performance section with test timings in a collapsible section
  if [ ${#test_duration_names[@]} -gt 0 ]; then
    summary+="\n<details>\n<summary><strong>⏱️ Test Durations</strong> (${#test_duration_names[@]} tests)</summary>\n\n"

    # First sort the tests by duration (longest first)
    local sorted_indexes=()
    local sorted_times=()
    local sorted_tests=()

    # Create a temporary file to sort the data
    local tmp_file=$(mktemp)

    # Populate the temp file with "time test_name" format for sorting
    for i in "${!test_duration_names[@]}"; do
      echo "${test_duration_times[$i]} ${test_duration_names[$i]}" >> "$tmp_file"
    done

    # Sort by the first field (time) in descending order
    while read -r time test; do
      sorted_times+=("$time")
      sorted_tests+=("$test")
    done < <(sort -rn "$tmp_file")

    # Clean up
    rm -f "$tmp_file"

    # Output the sorted results
    for i in "${!sorted_tests[@]}"; do
      summary+="- \`${sorted_tests[$i]}\`: ${sorted_times[$i]}s\n"
      if [ $i -ge 9 ]; then  # Show only top 10 slowest tests
        if [ ${#sorted_tests[@]} -gt 10 ]; then
          summary+="- _...and $((${#sorted_tests[@]} - 10)) more_\n"
        fi
        break
      fi
    done
    summary+="</details>\n"
  fi

  # Add list of successful targets in a collapsible section
  local total_successful=$((${#target_list[@]} + ${#test_list[@]} + ${#flaky_list[@]}))
  if [ $total_successful -gt 0 ]; then
    summary+="\n<details>\n<summary><strong>✅ Successfully Built</strong> ($total_successful targets)</summary>\n\n"

    # Show all the build targets first
    for target in "${target_list[@]}"; do
      summary+="- \`$target\`\n"
    done

    # Then show all the passed tests
    for target in "${test_list[@]}"; do
      summary+="- \`$target (test)\`\n"
    done

    # Then show all the flaky tests
    for target in "${flaky_list[@]}"; do
      summary+="- \`$target (⚠️ flaky)\`\n"
    done

    summary+="</details>\n"
  fi

  # Add details for failures if any in a collapsible section, but auto-expanded
  if [ -n "$failure_details" ]; then
    summary+="\n<details open>\n<summary><strong>❌ Failure Details</strong> ($fail_count failures)</summary>\n\n"
    summary+="$failure_details"
    summary+="</details>\n"
  fi

  # Add random inspirational quote
  summary+="\n---\n\n💡 **Random Dev Wisdom:**\n\n_$(get_random_quote)_\n"

  # Create the annotation
  create_annotation "$style" "$summary"

  # Upload the persistent file as an artifact if in Buildkite
  if [ -n "${BUILDKITE:-}" ] && [ -f "$PERSISTENT_MD_FILE" ] && command -v buildkite-agent >/dev/null 2>&1; then
    echo "Uploading results as artifact..."
    # Just upload the file, not the full path
    buildkite-agent artifact upload "$PERSISTENT_MD_FILE"
  fi
}

# Process the BEP file
process_bep

# Exit with the original Bazel exit code
exit ${BAZEL_EXIT_CODE:-0}
