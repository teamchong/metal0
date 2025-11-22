#!/usr/bin/env python3
"""
Debug the specific failures found in edge case testing
"""

import json
import subprocess
import tiktoken

enc = tiktoken.get_encoding('cl100k_base')

# Test case 1: All ASCII printable
print("=" * 70)
print("Test 1: All ASCII printable characters")
print("=" * 70)

text1 = "".join([chr(i) for i in range(32, 127)])
print(f"Text: {repr(text1)}")
print(f"Length: {len(text1)} chars")

expected1 = enc.encode(text1)
print(f"\nTiktoken ({len(expected1)} tokens):")
print(expected1)

result1 = subprocess.run(
    ['./zig-out/bin/test_correctness'],
    input=text1.encode('utf-8'),
    capture_output=True,
)
got1 = json.loads(result1.stderr.strip())
print(f"\nrs-bpe ({len(got1)} tokens):")
print(got1)

# Find differences
print("\nDifferences:")
for i, (exp, got) in enumerate(zip(expected1, got1)):
    if exp != got:
        print(f"  Position {i}: expected {exp}, got {got}")

if len(expected1) != len(got1):
    print(f"  Length mismatch: {len(expected1)} vs {len(got1)}")

# Test case 2: Numbers only
print("\n" + "=" * 70)
print("Test 2: Repeated numbers")
print("=" * 70)

text2 = "1234567890" * 100
print(f"Text: {repr(text2[:100])}... (repeated)")
print(f"Length: {len(text2)} chars")

expected2 = enc.encode(text2)
print(f"\nTiktoken ({len(expected2)} tokens):")
print(f"First 30: {expected2[:30]}")
print(f"Pattern check: {expected2[:30] == expected2[30:60]}")

result2 = subprocess.run(
    ['./zig-out/bin/test_correctness'],
    input=text2.encode('utf-8'),
    capture_output=True,
)
got2 = json.loads(result2.stderr.strip())
print(f"\nrs-bpe ({len(got2)} tokens):")
print(f"First 30: {got2[:30]}")
print(f"Pattern check: {got2[:30] == got2[30:60]}")

# Find where they diverge
print("\nFirst divergence:")
for i, (exp, got) in enumerate(zip(expected2, got2)):
    if exp != got:
        print(f"  Position {i}: expected {exp}, got {got}")
        print(f"  Context expected: {expected2[max(0,i-2):i+3]}")
        print(f"  Context got: {got2[max(0,i-2):i+3]}")
        break

# Decode tokens to see what they represent
print("\nDecoding first 10 tiktoken tokens:")
for i, tok in enumerate(expected2[:10]):
    decoded = enc.decode([tok])
    print(f"  {i}: {tok} -> {repr(decoded)}")

print("\nDecoding first 10 rs-bpe tokens:")
for i, tok in enumerate(got2[:10]):
    try:
        decoded = enc.decode([tok])
        print(f"  {i}: {tok} -> {repr(decoded)}")
    except:
        print(f"  {i}: {tok} -> INVALID TOKEN")

# Test simple number sequences
print("\n" + "=" * 70)
print("Test 3: Simple number sequences")
print("=" * 70)

for test_text in ["123", "1234", "12345", "123456", "1234567", "12345678", "123456789", "1234567890"]:
    exp = enc.encode(test_text)
    result = subprocess.run(
        ['./zig-out/bin/test_correctness'],
        input=test_text.encode('utf-8'),
        capture_output=True,
    )
    got = json.loads(result.stderr.strip())

    match = "✅" if exp == got else "❌"
    print(f"{match} '{test_text}': tiktoken={exp}, rs-bpe={got}")
