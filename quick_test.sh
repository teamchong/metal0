#!/bin/bash
cd /Users/steven_chong/Downloads/repos/metal0
passed=0
for f in tests/cpython/test_bool.py tests/cpython/test_int.py tests/cpython/test_unary.py tests/cpython/test_codecencodings_cn.py tests/cpython/test_codecencodings_hk.py tests/cpython/test_codecencodings_iso2022.py tests/cpython/test_codecencodings_jp.py tests/cpython/test_codecencodings_kr.py tests/cpython/test_codecencodings_tw.py tests/cpython/test_codecmaps_cn.py tests/cpython/test_codecmaps_hk.py tests/cpython/test_codecmaps_jp.py tests/cpython/test_codecmaps_kr.py tests/cpython/test_codecmaps_tw.py; do
  if [ -f "$f" ]; then
    result=$(timeout 60 ./zig-out/bin/metal0 "$f" --force 2>&1)
    if echo "$result" | grep -q "^OK"; then
      echo "PASS: $(basename $f)"
      passed=$((passed + 1))
    else
      echo "FAIL: $(basename $f)"
    fi
  fi
done
echo "Total passed: $passed"
