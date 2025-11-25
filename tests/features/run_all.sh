#!/bin/bash
cd "$(dirname "$0")/../.."

passed=0
failed=0
skipped=0
results=""

for f in tests/features/test_*.py; do
    name=$(basename $f .py | sed 's/test_//')
    output=$(pyaot $f --force 2>&1)
    if echo "$output" | grep -q "successfully"; then
        results="$results✓ $name\n"
        ((passed++))
    else
        results="$results✗ $name\n"
        ((failed++))
    fi
done

echo -e "$results"
echo "=== Summary ==="
echo "Passed: $passed"
echo "Failed: $failed"
total=$((passed + failed))
pct=$((passed * 100 / total))
echo "Coverage: $pct%"
