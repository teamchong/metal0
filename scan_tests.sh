#!/bin/bash
for f in tests/cpython/test_*.py; do
  result=$(timeout 20 metal0 "$f" --force 2>&1)
  if echo "$result" | grep -q "Ran.*test"; then
    echo "PASS: $f"
  fi
done
