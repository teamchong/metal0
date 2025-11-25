#!/bin/bash
# Run CPython tests against PyAOT
# Reports which tests pass/fail

passed=0
failed=0

for f in tests/reference/test_*.py; do
    # Skip if no matching files
    [ -e "$f" ] || continue

    name=$(basename "$f")
    if pyaot "$f" --force 2>&1 | grep -q "successfully"; then
        echo "✓ $name"
        ((passed++))
    else
        echo "✗ $name"
        ((failed++))
    fi
done

echo ""
echo "Summary: $passed passed, $failed failed"
