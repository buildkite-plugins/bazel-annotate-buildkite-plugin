#!/bin/bash
set -euo pipefail

PLUGIN_PREFIX="BAZEL_BEP_ANNOTATE"

# Reads either a value or a list from the given env prefix
function prefix_read_list() {
  local prefix="$1"
  local parameter="${prefix}_0"

  if [ -n "${!parameter:-}" ]; then
    local i=0
    local parameter="${prefix}_${i}"
    while [ -n "${!parameter:-}" ]; do
      echo "${!parameter}"
      i=$((i+1))
      parameter="${prefix}_${i}"
    done
  elif [ -n "${!prefix:-}" ]; then
    echo "${!prefix}"
  fi
}

# Reads either a value or a list from plugin config
function plugin_read_list() {
  prefix_read_list "BUILDKITE_PLUGIN_${PLUGIN_PREFIX}_${1}"
}


# Reads either a value or a list from plugin config into a global result array
# Returns success if values were read
function prefix_read_list_into_result() {
  local prefix="$1"
  local parameter="${prefix}_0"
  result=()

  if [ -n "${!parameter:-}" ]; then
    local i=0
    local parameter="${prefix}_${i}"
    while [ -n "${!parameter:-}" ]; do
      result+=("${!parameter}")
      i=$((i+1))
      parameter="${prefix}_${i}"
    done
  elif [ -n "${!prefix:-}" ]; then
    result+=("${!prefix}")
  fi

  [ ${#result[@]} -gt 0 ] || return 1
}

# Reads either a value or a list from plugin config
function plugin_read_list_into_result() {
  prefix_read_list_into_result "BUILDKITE_PLUGIN_${PLUGIN_PREFIX}_${1}"
}

# Reads a single value
function plugin_read_config() {
  local key="${1}"
  local default="${2:-}"
  local var="BUILDKITE_PLUGIN_${PLUGIN_PREFIX}_${key}"
  
  # Debug logging
  echo "DEBUG: Looking for env var: ${var}"
  echo "DEBUG: Current value: ${!var:-<not set>}"
  
  # Also check alternative case formats (this is the fix)
  if [[ -z "${!var:-}" ]]; then
    # Try lowercase version
    local lowercase_key=$(echo "${key}" | tr '[:upper:]' '[:lower:]')
    local lowercase_var="BUILDKITE_PLUGIN_${PLUGIN_PREFIX}_${lowercase_key}"
    echo "DEBUG: Also trying lowercase: ${lowercase_var}"
    echo "DEBUG: Lowercase value: ${!lowercase_var:-<not set>}"
    
    if [[ -n "${!lowercase_var:-}" ]]; then
      echo "DEBUG: Using lowercase variant: ${!lowercase_var}"
      echo "${!lowercase_var}"
      return
    fi
  fi
  
  echo "${!var:-$default}"
}
