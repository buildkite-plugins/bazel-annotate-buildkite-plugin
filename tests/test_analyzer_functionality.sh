#!/bin/bash
set -euo pipefail

# Test analyzer functionality using shell

echo "Testing analyzer functionality..."

ANALYZER="bin/bazel_failure_analyzer"

# Test 1: Help command
echo "Testing help command..."
if ! "$ANALYZER" --help >/dev/null 2>&1; then
    echo "ERROR: Help command failed"
    exit 1
fi
echo "✅ Help command works"

# Test 2: Missing file handling
echo "Testing missing file handling..."
if "$ANALYZER" /nonexistent/file.pb >/dev/null 2>&1; then
    echo "ERROR: Should fail for missing file"
    exit 1
fi
echo "✅ Missing file handling works"

# Test 3: Empty file handling
echo "Testing empty file handling..."
TEMP_DIR=$(mktemp -d)
touch "$TEMP_DIR/empty.pb"

if ! "$ANALYZER" "$TEMP_DIR/empty.pb" --skip-if-no-failures >/dev/null 2>&1; then
    echo "ERROR: Empty file should be handled gracefully"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "✅ Empty file handling works"

# Test 4: Different output formats
echo "Testing output formats..."
for format in text json buildkite; do
    if ! "$ANALYZER" "$TEMP_DIR/empty.pb" --output-format="$format" --skip-if-no-failures >/dev/null 2>&1; then
        echo "ERROR: Output format $format failed"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo "✅ Output format $format works"
done

# Test 5: Verbose mode
echo "Testing verbose mode..."
if ! "$ANALYZER" "$TEMP_DIR/empty.pb" --verbose --skip-if-no-failures >/dev/null 2>&1; then
    echo "ERROR: Verbose mode failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo "✅ Verbose mode works"

# Clean up
rm -rf "$TEMP_DIR"

echo "🎉 All analyzer functionality tests passed!"
