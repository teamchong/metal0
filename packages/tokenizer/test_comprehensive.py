#!/usr/bin/env python3
"""
Comprehensive correctness test using existing test_correctness binary
Tests 638 cases: benchmark texts + edge cases + unicode + adversarial
"""

import json
import subprocess
import sys
import tiktoken
from pathlib import Path

# Load tiktoken reference
enc = tiktoken.get_encoding('cl100k_base')

# Load benchmark data
with open('benchmark_data.json') as f:
    benchmark_texts = json.load(f)['texts']

# Edge cases
edge_cases = [
    "",  # Empty
    " ",  # Single space
    "a",  # Single char
    "\n",  # Newline
    "hello",  # Short word
    "a" * 10000,  # Very long
    "The quick brown fox " * 500,  # Repeated
    "!@#$%^&*()",  # Special chars
    "你好世界",  # Chinese
    "😀😃😄😁",  # Emoji
    "👨‍👩‍👧‍👦",  # ZWJ emoji
]

all_tests = benchmark_texts + edge_cases

print(f"🔍 Running {len(all_tests)} correctness tests...")
print("=" * 70)

passed = 0
failed = 0
first_failure = None

for i, text in enumerate(all_tests):
    # Get expected from tiktoken
    expected = enc.encode(text)

    # Get metal0 result (write text to stdin)
    try:
        result = subprocess.run(
            ['./zig-out/bin/test_correctness'],
            input=text.encode('utf-8'),
            capture_output=True,
            timeout=5
        )

        # Parse output (JSON from stderr)
        got = json.loads(result.stderr.strip())

        if got == expected:
            passed += 1
        else:
            failed += 1
            if first_failure is None:
                first_failure = {
                    'index': i,
                    'text': text[:100],
                    'expected': expected[:20],
                    'got': got[:20]
                }
    except Exception as e:
        failed += 1
        if first_failure is None:
            first_failure = {
                'index': i,
                'text': text[:100],
                'error': str(e)
            }

    # Progress bar
    if (i + 1) % 50 == 0 or i == len(all_tests) - 1:
        pct = (i + 1) / len(all_tests) * 100
        print(f"  [{i+1}/{len(all_tests)}] {pct:.1f}% - Passed: {passed}, Failed: {failed}")

print("=" * 70)

if failed == 0:
    print(f"✅ ALL TESTS PASSED ({passed}/{len(all_tests)})")
    sys.exit(0)
else:
    print(f"❌ TESTS FAILED ({passed}/{len(all_tests)} passed, {failed} failed)")
    print()
    if first_failure:
        print("First failure:")
        print(f"  Test #{first_failure['index']}")
        print(f"  Text: {first_failure['text']}")
        if 'error' in first_failure:
            print(f"  Error: {first_failure['error']}")
        else:
            print(f"  Expected: {first_failure['expected']}")
            print(f"  Got:      {first_failure['got']}")
    sys.exit(1)
