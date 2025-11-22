#!/usr/bin/env python3
"""
Investigate tiktoken's pattern-based pre-tokenization
"""

import tiktoken
import regex as re

enc = tiktoken.get_encoding('cl100k_base')

# Check tiktoken's pattern
print("=" * 70)
print("Tiktoken Pattern Analysis")
print("=" * 70)

pattern = enc._pat_str
print(f"Pattern: {pattern}\n")

# Compile and test the pattern
compiled_pattern = re.compile(pattern)

# Test on our problematic text
test_texts = [
    "7890",
    "1234567890",
    "123",
    "1234",
]

print("Pattern-based pre-tokenization:")
for text in test_texts:
    matches = compiled_pattern.findall(text)
    print(f"  '{text}' -> {matches}")

print("\n" + "=" * 70)
print("This explains the difference!")
print("=" * 70)
print()
print("Tiktoken uses regex pre-tokenization that splits text into chunks")
print("BEFORE applying BPE. Each chunk is tokenized independently.")
print()
print("For '1234567890', the pattern might split it differently than")
print("treating it as one continuous sequence.")

# Let's manually check by looking at how tiktoken actually encodes
print("\n" + "=" * 70)
print("Detailed tokenization trace")
print("=" * 70)

for text in ["7890", "1234567890"]:
    print(f"\nText: '{text}'")
    print(f"  Pre-tokenization chunks: {compiled_pattern.findall(text)}")
    tokens = enc.encode(text)
    decoded = [enc.decode([t]) for t in tokens]
    print(f"  Tokens: {tokens}")
    print(f"  Decoded: {decoded}")

# The key insight: check if tiktoken uses different algorithm
print("\n" + "=" * 70)
print("Checking if pattern affects number sequences")
print("=" * 70)

# Try with spaces to see if pattern changes behavior
test_with_spaces = [
    ("7890", "continuous"),
    ("7 8 9 0", "with spaces"),
    ("789 0", "split after 789"),
    ("78 90", "split at 78/90"),
]

for text, desc in test_with_spaces:
    chunks = compiled_pattern.findall(text)
    tokens = enc.encode(text)
    decoded = [enc.decode([t]) for t in tokens]
    print(f"{desc:20s}: chunks={chunks}, tokens={decoded}")
