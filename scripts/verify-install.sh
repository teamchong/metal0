#!/bin/bash
# Verify metal0 installation

set -e

echo "🔍 Verifying metal0 installation..."
echo ""

# Check metal0 command exists
if command -v metal0 >/dev/null 2>&1; then
    echo "✅ metal0 command found in PATH"
else
    echo "❌ metal0 command not found"
    echo "   Run: source .venv/bin/activate"
    exit 1
fi

# Test help
echo "✅ Testing --help..."
metal0 --help >/dev/null

# Test compilation
echo "✅ Testing compilation..."
metal0 examples/fibonacci.py -o /tmp/metal0_verify_test >/dev/null 2>&1

# Test execution
echo "✅ Testing execution..."
OUTPUT=$(/tmp/metal0_verify_test 2>&1)
if [ "$OUTPUT" = "55" ]; then
    echo "✅ Output correct: $OUTPUT"
else
    echo "❌ Output incorrect: '$OUTPUT' (expected '55')"
    exit 1
fi

# Clean up
rm -f /tmp/metal0_verify_test

echo ""
echo "✅ All checks passed! metal0 is properly installed."
echo ""
echo "Try: metal0 examples/fibonacci.py --run"
echo ""
