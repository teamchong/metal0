#!/usr/bin/env python3
"""
Comprehensive encoding correctness test

Tests metal0 encoding against tiktoken (ground truth) on:
1. All 583 benchmark texts
2. Edge cases (unicode, special chars, empty, very long)
3. Random samples

PASS = 100% match on ALL tests, FAIL = any single mismatch
"""

import subprocess
import tiktoken
import json
import sys

# Load all benchmark texts
with open('benchmark_data.json') as f:
    benchmark_texts = json.load(f)['texts']

# Edge cases
EDGE_CASES = [
    "",  # Empty
    " ",  # Single space
    "\n",  # Newline
    "a",  # Single char
    "The quick brown fox jumps over the lazy dog.",
    "1234567890" * 100,  # Long numbers
    "!@#$%^&*()_+-=[]{}|;:',.<>?/~`",  # Special chars
    "你好世界",  # Chinese
    "🌍🚀💻🎉",  # Emojis
    "a" * 10000,  # Very long (10K chars)
    benchmark_texts[0],  # Shortest benchmark
    max(benchmark_texts, key=len),  # Longest benchmark
]

ALL_TESTS = benchmark_texts + EDGE_CASES

print("🔍 Encoding Correctness Test (100% Match Required)")
print("=" * 70)
print(f"Testing: {len(ALL_TESTS)} texts")
print(f"  - {len(benchmark_texts)} benchmark texts")
print(f"  - {len(EDGE_CASES)} edge cases")
print()

# Initialize tiktoken
enc = tiktoken.get_encoding('cl100k_base')

# Test each text
failures = []
for i, text in enumerate(ALL_TESTS):
    # Get expected tokens from tiktoken
    expected = enc.encode(text)

    # Get metal0 tokens
    # TODO: Need a way to call metal0 encoder programmatically!
    # Currently test_correctness only works for hardcoded TEXT

    print(f"❌ CRITICAL: Cannot test metal0 encoding programmatically!")
    print(f"   test_correctness.py has hardcoded TEXT")
    print(f"   Need metal0 to expose encode(text) function")
    break

print()
print("=" * 70)
print("📋 What we need for 100% correctness verification:")
print()
print("1. **Encoding:**")
print("   - Expose metal0 encode() as callable function")
print("   - Test ALL 583 benchmark texts + edge cases")
print("   - Every token ID must match tiktoken exactly")
print()
print("2. **Training:**")
print("   - Save trained vocab/merges to JSON")
print("   - Compare with HuggingFace trained vocab")
print("   - Encode test set with both, compare results")
print()
print("3. **Current Status:**")
print("   ❌ Training: Cannot verify (doesn't save model)")
print("   ❌ Encoding: Only tests 1 hardcoded text")
print()
print("=" * 70)
print("⚠️  RECOMMENDATION: Add correctness verification BEFORE optimizing!")
print("   Speed means nothing if results are wrong.")
print("=" * 70)
