#!/bin/bash
cd "$(dirname "$0")/../.."

passed=0
failed=0
pass_list=""
fail_list=""

for f in tests/features/test_*.py; do
    name=$(basename $f .py | sed 's/test_//')
    output=$(./zig-out/bin/pyaot $f --force 2>&1)
    if echo "$output" | grep -q "successfully"; then
        pass_list="$pass_list $name"
        ((passed++))
    else
        fail_list="$fail_list $name"
        ((failed++))
    fi
done

echo "=== Results ==="
echo "✓ Passed:$pass_list"
echo "✗ Failed:$fail_list"
echo ""
echo "=== Summary ==="
echo "Passed: $passed"
echo "Failed: $failed"
total=$((passed + failed))
pct=$((passed * 100 / total))
echo "Coverage: $pct%"
