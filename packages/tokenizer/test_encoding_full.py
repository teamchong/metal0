#!/usr/bin/env python3
"""
Full encoding correctness test - 601 cases (592 benchmark + 9 edge cases)
Uses existing test_correctness binary with stdin input.
"""

import json
import subprocess
import sys
import tiktoken
from concurrent.futures import ThreadPoolExecutor, as_completed

# Load tiktoken
enc = tiktoken.get_encoding('cl100k_base')

# Load benchmark data
with open('benchmark_data.json') as f:
    benchmark_texts = json.load(f)['texts']

# Edge cases
edge_cases = [
    "",
    " ",
    "a",
    "\n",
    "hello",
    "The quick brown fox jumps over the lazy dog.",
    "!@#$%^&*()",
    "你好世界",
    "😀😃😄😁",
]

all_texts = benchmark_texts + edge_cases

print(f"🔍 Encoding Correctness Test")
print(f"=" * 70)
print(f"Testing {len(all_texts)} texts ({len(benchmark_texts)} benchmark + {len(edge_cases)} edge cases)")
print()

def test_single(args):
    """Test a single text and return (index, passed, failure_info)"""
    i, text = args
    expected = enc.encode(text)

    try:
        result = subprocess.run(
            ['./zig-out/bin/test_correctness'],
            input=text.encode('utf-8'),
            capture_output=True,
            timeout=30  # Increased for ~7s load time with cache
        )
        got = json.loads(result.stderr.strip())

        if got == expected:
            return (i, True, None)
        else:
            return (i, False, {
                'index': i,
                'text': text[:50] + ('...' if len(text) > 50 else ''),
                'expected': expected[:10],
                'got': got[:10],
                'expected_len': len(expected),
                'got_len': len(got),
            })
    except Exception as e:
        return (i, False, {'index': i, 'text': text[:50], 'error': str(e)})

# Run tests in parallel
print("Running tests (parallel)...")
passed = 0
failed = 0
first_failure = None

with ThreadPoolExecutor(max_workers=8) as executor:
    futures = {executor.submit(test_single, (i, text)): i for i, text in enumerate(all_texts)}

    completed = 0
    for future in as_completed(futures):
        i, success, failure_info = future.result()
        completed += 1

        if success:
            passed += 1
        else:
            failed += 1
            if first_failure is None:
                first_failure = failure_info

        # Progress
        if completed % 50 == 0 or completed == len(all_texts):
            print(f"  Progress: {completed}/{len(all_texts)} ({passed} passed, {failed} failed)")

print()
print("=" * 70)
print(f"Results: {passed}/{len(all_texts)} passed, {failed} failed")
print()

if failed == 0:
    print("✅ 100% CORRECT - All tokens match tiktoken!")
    sys.exit(0)
else:
    accuracy = passed / len(all_texts) * 100
    print(f"❌ {failed} tests failed ({accuracy:.1f}% accuracy)")
    if first_failure:
        print()
        print("First failure:")
        print(f"  Test #{first_failure['index']}")
        print(f"  Text: {first_failure['text']!r}")
        if 'error' in first_failure:
            print(f"  Error: {first_failure['error']}")
        else:
            print(f"  Expected ({first_failure['expected_len']} tokens): {first_failure['expected']}")
            print(f"  Got ({first_failure['got_len']} tokens): {first_failure['got']}")
    sys.exit(1)
