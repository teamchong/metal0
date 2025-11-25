#!/bin/bash
# Run CPython tests against PyAOT
# Reports which tests pass/fail

cd "$(dirname "$0")/../.."

passed=0
failed=0

for f in tests/cpython/test_*.py; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if ./zig-out/bin/pyaot "$f" --force 2>&1 | grep -q "successfully"; then
        echo "✓ $name"
        ((passed++))
    else
        ((failed++))
    fi
done

total=$((passed + failed))
echo ""
echo "=== CPython Test Baseline ==="
echo "Passed: $passed / $total"
echo "Failed: $failed"
if [ $total -gt 0 ]; then
    echo "Pass rate: $((passed * 100 / total))%"
fi
