#!/usr/bin/env python3
"""
Edge case testing for rs-bpe vs tiktoken
Tests adversarial inputs that might reveal bugs
"""

import json
import subprocess
import sys
import tiktoken
from pathlib import Path

# Load tiktoken reference
enc = tiktoken.get_encoding('cl100k_base')

# Define edge cases
edge_cases = {
    "Empty string": "",
    "Single space": " ",
    "Single char": "a",
    "Simple word": "The",
    "Chinese text": "你好世界",
    "Emoji sequence": "😀😃😄😁",
    "ZWJ emoji": "👨‍👩‍👧‍👦",
    "Very long repeated": "a" * 1000,
    "All ASCII printable": "".join([chr(i) for i in range(32, 127)]),
    "Multiple newlines": "\n\n\n\n",
    "Multiple spaces": "    ",
    "Mixed whitespace": " \t\n\r ",
    "Special chars": "!@#$%^&*()",
    "Unicode combining": "e\u0301",  # é as e + combining acute
    "Right-to-left": "مرحبا بك",  # Arabic
    "Null-like": "\x00",
    "High Unicode": "\U0001F600",  # Emoji via escape
    "Mixed scripts": "Hello 世界 مرحبا",
    "Repeated phrase": "The quick brown fox " * 100,
    "Numbers only": "1234567890" * 100,
}

print("🔍 Edge Case Testing: rs-bpe vs tiktoken")
print("=" * 70)

passed = 0
failed = 0
failures = []

for name, text in edge_cases.items():
    # Get expected from tiktoken
    try:
        expected = enc.encode(text)
    except Exception as e:
        print(f"⚠️  {name}: tiktoken error: {e}")
        continue

    # Get rs-bpe result via test_correctness binary
    result = None
    try:
        result = subprocess.run(
            ['./zig-out/bin/test_correctness'],
            input=text.encode('utf-8'),
            capture_output=True,
            timeout=5
        )

        got = json.loads(result.stderr.strip())

        if got == expected:
            print(f"✅ {name}")
            passed += 1
        else:
            print(f"❌ {name}")
            failed += 1
            failures.append({
                'name': name,
                'text': text[:100] if len(text) <= 100 else text[:97] + "...",
                'text_len': len(text),
                'expected': expected[:20] if len(expected) > 20 else expected,
                'expected_len': len(expected),
                'got': got[:20] if len(got) > 20 else got,
                'got_len': len(got),
            })
    except subprocess.TimeoutExpired:
        print(f"⏱️  {name}: TIMEOUT")
        failed += 1
        failures.append({
            'name': name,
            'text': text[:100],
            'error': 'Timeout after 5s'
        })
    except json.JSONDecodeError as e:
        print(f"❌ {name}: JSON parse error")
        failed += 1
        stderr_text = result.stderr.decode('utf-8', errors='replace')[:200] if result else "N/A"
        failures.append({
            'name': name,
            'text': text[:100],
            'error': f'JSON error: {e}',
            'stderr': stderr_text
        })
    except Exception as e:
        print(f"❌ {name}: {type(e).__name__}")
        failed += 1
        failures.append({
            'name': name,
            'text': text[:100],
            'error': str(e)
        })

print("=" * 70)
print(f"Results: {passed} passed, {failed} failed out of {len(edge_cases)} tests")
print()

# Show detailed failures
if failures:
    print("FAILURES:")
    print("-" * 70)
    for f in failures:
        print(f"\n{f['name']}:")
        print(f"  Text: {repr(f['text'])}")
        if 'error' in f:
            print(f"  Error: {f['error']}")
            if 'stderr' in f:
                print(f"  Stderr: {f['stderr']}")
        else:
            print(f"  Text length: {f['text_len']}")
            print(f"  Expected ({f['expected_len']} tokens): {f['expected']}")
            print(f"  Got ({f['got_len']} tokens): {f['got']}")
            if f['expected_len'] != f['got_len']:
                print(f"  ⚠️  Token count mismatch: {f['expected_len']} vs {f['got_len']}")
    print("-" * 70)

# Test boundary cases from benchmark_data.json
print("\n🔍 Testing adversarial cases from benchmark_data.json...")
print("=" * 70)

try:
    with open('benchmark_data.json') as f:
        data = json.load(f)
        texts = data['texts']

    # Find interesting cases
    longest_text = max(texts, key=len)
    most_tokens_text = max(texts, key=lambda t: len(enc.encode(t)))

    adversarial_tests = {
        "Longest text": longest_text,
        "Most tokens": most_tokens_text,
    }

    adv_passed = 0
    adv_failed = 0

    for name, text in adversarial_tests.items():
        expected = enc.encode(text)

        try:
            result = subprocess.run(
                ['./zig-out/bin/test_correctness'],
                input=text.encode('utf-8'),
                capture_output=True,
                timeout=10
            )

            got = json.loads(result.stderr.strip())

            if got == expected:
                print(f"✅ {name} ({len(text)} chars, {len(expected)} tokens)")
                adv_passed += 1
            else:
                print(f"❌ {name} ({len(text)} chars)")
                print(f"   Expected: {len(expected)} tokens")
                print(f"   Got: {len(got)} tokens")
                adv_failed += 1
        except Exception as e:
            print(f"❌ {name}: {type(e).__name__}: {e}")
            adv_failed += 1

    print("=" * 70)
    print(f"Adversarial: {adv_passed} passed, {adv_failed} failed")

except FileNotFoundError:
    print("⚠️  benchmark_data.json not found, skipping adversarial tests")
except Exception as e:
    print(f"⚠️  Error loading benchmark data: {e}")

# Final summary
print("\n" + "=" * 70)
print("CONCLUSION:")
if failed == 0:
    print("✅ rs-bpe handles ALL edge cases correctly!")
else:
    print(f"❌ rs-bpe has issues with {failed}/{len(edge_cases)} edge cases")
    print("   Review failures above for debugging")

sys.exit(0 if failed == 0 else 1)
