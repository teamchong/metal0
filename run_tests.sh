#!/bin/bash
# Run CPython tests and categorize results

passed=0
failed=0
errors=""

for f in tests/cpython/test_*.py; do
    name=$(basename "$f" .py)
    result=$(./zig-out/bin/metal0 "$f" --force 2>&1)
    if echo "$result" | grep -q "Compiled successfully"; then
        echo "OK: $name"
        passed=$((passed + 1))
    else
        echo "FAIL: $name"
        failed=$((failed + 1))
        # Get first error
        err=$(echo "$result" | grep "error:" | head -1)
        errors="$errors\n$name: $err"
    fi
done

echo ""
echo "================================"
echo "Passed: $passed"
echo "Failed: $failed"
echo "================================"
