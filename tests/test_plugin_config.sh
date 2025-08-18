#!/bin/bash
set -euo pipefail

# Simple test for plugin configuration
echo "Testing plugin configuration..."

# Test 1: Check plugin.yml exists and is valid
if [[ ! -f "plugin.yml" ]]; then
    echo "ERROR: plugin.yml not found"
    exit 1
fi

echo "✅ plugin.yml exists"

# Test 2: Check required files exist
REQUIRED_FILES=(
    "hooks/post-command"
    "lib/plugin.bash"
    "bin/bazel_failure_analyzer"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file $file not found"
        exit 1
    fi
    echo "✅ $file exists"
done

# Test 3: Check executability
EXECUTABLE_FILES=(
    "hooks/post-command"
    "bin/bazel_failure_analyzer"
)

for file in "${EXECUTABLE_FILES[@]}"; do
    if [[ ! -x "$file" ]]; then
        echo "ERROR: $file is not executable"
        exit 1
    fi
    echo "✅ $file is executable"
done

# Test 4: Check analyzer help
if ! ./bin/bazel_failure_analyzer --help >/dev/null 2>&1; then
    echo "ERROR: Analyzer help command failed"
    exit 1
fi

echo "✅ Analyzer help works"

echo "🎉 All plugin configuration tests passed!"
