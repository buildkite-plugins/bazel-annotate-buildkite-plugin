#!/bin/bash
set -euo pipefail

# This library processes Bazel Event Protocol output and creates Buildkite annotations

# Function to get random quote for annotation footer
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

# Function to create a Buildkite annotation with the given style and content
create_annotation() {
  local style="$1"
  local content="$2"
  local context_id="bazel-bep-results"
  local job_name="${BUILDKITE_LABEL:-Unknown Job}"
  local is_first_job="${BUILDKITE_PLUGIN_BAZEL_ANNOTATE_IS_FIRST_JOB:-true}"

  # Check if we're running in Buildkite
  if [ -n "${BUILDKITE:-}" ] && command -v buildkite-agent >/dev/null 2>&1; then
    # Modify content based on whether this is the first job
    if [ "$is_first_job" != "true" ]; then
      # If not the first job, add a job section instead of the main header
      echo "Appending to existing Buildkite annotation..."
      
      # Replace the main header with a job-specific header or remove it
      content=$(echo "$content" | sed '1,3d') # Remove the first 3 lines (header + blank line)
      
      # Add job-specific section header
      content="### 🧩 ${job_name}\n\n${content}"
    else
      echo "Creating initial Buildkite annotation with header..."
    fi
    
    # Use printf to ensure newlines are properly interpreted
    printf "%s" "$content" | buildkite-agent annotate --style "$style" --context "$context_id" --append
    
    # Signal to future jobs that they're not the first
    if buildkite-agent meta-data exists "bazel-annotate-header-created" 2>/dev/null; then
      echo "Header already marked as created in metadata"
    else
      echo "Setting metadata to indicate header has been created"
      buildkite-agent meta-data set "bazel-annotate-header-created" "true" || true
    fi
  else
    # We're not in Buildkite, just display the content on stdout
    echo "Not running in Buildkite. Would create annotation with style '$style':"
    # Use printf to properly display the markdown
    printf "%s" "$content"
  fi
}

# Process the BEP file to extract useful information
process_bep() {
  local BEP_FILE="$1"

  # Ensure the file exists
  if [[ ! -f "$BEP_FILE" ]]; then
    echo "Error: BEP file does not exist: $BEP_FILE"
    return 1
  fi

  # Count of target statuses
  local success_count=0
  local fail_count=0
  local skip_count=0
  local cached_count=0

  # Arrays for successful targets
  declare -a successful_targets=()
  declare -a successful_targets_sorted=()

  # Arrays for test performance tracking
  declare -a slowest_tests=()
  declare -a slowest_times=()
  local slowest_count=0

  # Collect failures for detailed annotation
  local failure_details=""

  # Performance data
  local build_start_time=0
  local build_end_time=0

  echo "Processing BEP file: $BEP_FILE"

  # Parse the JSON stream
  while read -r line || [[ -n "$line" ]]; do
    # Skip empty lines
    if [ -z "$line" ]; then
      continue
    fi

    # Try to parse as JSON, but continue on errors
    if ! echo "$line" | jq -e '.' > /dev/null 2>&1; then
      echo "Warning: Skipping invalid JSON line: ${line:0:50}..."
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
      local label
      label=$(echo "$line" | jq -r '.id.targetCompleted.label // "unknown"')
      local success
      success=$(echo "$line" | jq -r '.completed.success // "false"')
      # shellcheck disable=SC2034
      local is_cached=false

      # Check if the target was cached
      if echo "$line" | jq -e '.completed.outputGroup != null and (.completed.outputGroup[] | select(.name == "bazel-out") | .fileSets[] | select(.id != null))' > /dev/null 2>&1; then
        # If it has output files but doesn't have actionExecuted, it's likely cached
        if ! echo "$line" | jq -e '.completed.actionExecuted != null' > /dev/null 2>&1; then
          # is_cached flag set for potential future use
          # shellcheck disable=SC2034
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
        local errors
        errors=$(echo "$line" | jq -r '.completed.failureDetail.message // "Unknown error"')
        failure_details+="### ❌ Failed: $label
\`\`\`diff
- ERROR: $errors
\`\`\`

"
        # Check for missing dependency or deleted package errors
        if echo "$errors" | grep -q "no such target\|no such package\|Package is considered deleted"; then
          # Extract relevant part of the error message
          local error_detail
          error_detail=$(echo "$errors" | grep -o "'[^']*'\|Package [^:]*" | head -1)
          failure_details+="**🔍 Possible Fix:** $error_detail might be missing, renamed, or deleted. Add it to --deleted_packages flag if it's intentionally deleted.

"
        fi
      fi
    fi

    # Also check for configured targets
    if echo "$line" | jq -e '.id.configured != null' > /dev/null 2>&1; then
      local label
      label=$(echo "$line" | jq -r '.id.configured.targetLabel // "unknown"')
      # Using a simple pattern match to check if the label is in the array
      # Avoiding regex comparison which causes shellcheck warning
      if [[ ! " ${successful_targets[*]} " == *" $label "* ]]; then
        # Only add if it's not already counted
        ((success_count++))
        successful_targets+=("$label")
      fi
    fi

    # Extract skipped targets
    if echo "$line" | jq -e '.id.targetSkipped != null' > /dev/null 2>&1; then
      local label
      label=$(echo "$line" | jq -r '.id.targetSkipped.label // "unknown"')
      ((skip_count++))
    fi

    # Extract test results if available
    if echo "$line" | jq -e '.id.testResult != null' > /dev/null 2>&1; then
      local test_label
      test_label=$(echo "$line" | jq -r '.id.testResult.label // "unknown"')
      local test_status
      test_status=$(echo "$line" | jq -r '.testResult.status // "UNKNOWN"')
      local test_time
      test_time=$(echo "$line" | jq -r '.testResult.testActionDurationMillis // 0')

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
      slowest_tests[slowest_count]="$test_label"
      slowest_times[slowest_count]="$test_time"
      ((slowest_count++))

      if [ "$test_status" != "PASSED" ]; then
        # Get test failure details if available
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

        failure_details+="### $status_emoji Failed Test: $test_label ($test_status in ${test_time}s)
\`\`\`diff
- $test_errors
\`\`\`

"

        # Add stack trace if available
        if echo "$line" | jq -e 'has("testResult") and .testResult | has("testActionOutput") and .testResult.testActionOutput != null' > /dev/null 2>&1; then
          if echo "$line" | jq -e '.testResult.testActionOutput[] | select(.name == "test.log") | .uri' > /dev/null 2>&1; then
            local log_uri
            log_uri=$(echo "$line" | jq -r '.testResult.testActionOutput[] | select(.name == "test.log") | .uri')
            failure_details+="[View Full Test Log]($log_uri)

"
          fi
        fi
      fi
    fi
  done < "$BEP_FILE"

  # Calculate total build time
  local total_build_time=0
  if [ "$build_end_time" -gt 0 ] && [ "$build_start_time" -gt 0 ]; then
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

  # Use job-specific header 
  local job_label="${BUILDKITE_LABEL:-Bazel Results}"
  # Simple, clean job header
  local summary="### ${job_label}

"
  # Add command used if running in Buildkite
  if [ -n "${BUILDKITE_COMMAND:-}" ]; then
    summary+="**🏃 Command:** \`${BUILDKITE_COMMAND}\`

"
  fi

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
  summary+="

"

  # Add performance section with test timings in a collapsible section
  if [ ${#slowest_tests[@]} -gt 0 ]; then
    summary+="<details>
<summary><strong>⏱️ Test Durations</strong> (${#slowest_tests[@]} tests)</summary>

"

    # First sort the tests by duration (longest first)
    # sorted_indexes is kept for potential future implementation of index tracking
    # or for maintaining references to original array positions
    # shellcheck disable=SC2034
    local sorted_indexes=()
    local sorted_times=()
    local sorted_tests=()

    # Create a temporary file to sort the data
    local tmp_file
    tmp_file=$(mktemp)

    # Populate the temp file with "time test_name" format for sorting
    for i in "${!slowest_tests[@]}"; do
      echo "${slowest_times[$i]} ${slowest_tests[$i]}" >> "$tmp_file"
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
      summary+="- \`${sorted_tests[$i]}\`: ${sorted_times[$i]}s
"
      if [ "$i" -ge 9 ]; then  # Show only top 10 slowest tests
        if [ ${#sorted_tests[@]} -gt 10 ]; then
          summary+="- _...and $((${#sorted_tests[@]} - 10)) more_
"
        fi
        break
      fi
    done
    summary+="</details>
"
  fi

  # Add list of successful targets in a collapsible section
  if [ ${#successful_targets[@]} -gt 0 ]; then
    summary+="
<details>
<summary><strong>✅ Successfully Built</strong> (${#successful_targets[@]} targets)</summary>

"

if [ ${#successful_targets[@]} -gt 0 ]; then
  mapfile -t successful_targets_sorted < <(printf '%s\n' "${successful_targets[@]}" | sort)
fi

    # Show all targets
    for target in "${successful_targets_sorted[@]}"; do
      summary+="- \`$target\`
"
    done

    summary+="</details>
"
  fi

  # Add details for failures if any in a collapsible section, but auto-expanded
  if [ -n "$failure_details" ]; then
    summary+="
<details open>
<summary><strong>❌ Failure Details</strong> ($fail_count failures)</summary>

$failure_details</details>
"
  fi

  # Add extra spacing between appended annotations for better readability
  summary+="


---


"

  # Create the annotation
  create_annotation "$style" "$summary"

  # Always return success after processing
  return 0
}
