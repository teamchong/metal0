#!/bin/bash
cd /Users/steven_chong/Downloads/repos/metal0
for f in tests/cpython/test_*.py; do
    result=$(timeout 90 ./zig-out/bin/metal0 "$f" --force 2>&1)
    if echo "$result" | grep -q "^OK"; then
        echo "PASS: $(basename $f)"
    elif echo "$result" | grep -q "ZigCompilationFailed"; then
        echo "FAIL-COMPILE: $(basename $f)"
    else
        echo "FAIL-RUN: $(basename $f)"
    fi
done
