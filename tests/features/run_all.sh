#!/bin/bash
# Run all feature tests

cd "$(dirname "$0")/../.."

passed=0
failed=0
failed_tests=""

for f in tests/features/test_*.py; do
    name=$(basename $f .py | sed 's/test_//')
    if pyaot $f --force 2>&1 | grep -q "successfully"; then
        echo "✓ $name"
        ((passed++))
    else
        echo "✗ $name"
        ((failed++))
        failed_tests="$failed_tests $name"
    fi
done

echo ""
echo "=== Summary ==="
echo "Passed: $passed"
echo "Failed: $failed"
if [ -n "$failed_tests" ]; then
    echo "Failed tests:$failed_tests"
fi
