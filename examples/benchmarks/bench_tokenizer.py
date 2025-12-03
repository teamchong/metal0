"""
Tokenizer benchmark - metal0 native Zig BPE tokenizer.

Usage:
    metal0 bench_tokenizer.py
"""

from metal0 import tokenizer
import time

# Initialize tokenizer
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Sample texts for benchmarking
SAMPLE_TEXTS = [
    "Hello, world!",
    "The quick brown fox jumps over the lazy dog.",
    "Machine learning is transforming how we build software.",
    "Python is a great language for data science and AI.",
    "Tokenization is the first step in natural language processing.",
]

iterations = 100

print("=" * 50)
print("metal0 Tokenizer Benchmark (native Zig BPE)")
print("=" * 50)

# Warm up
print("\nWarming up...")
for text in SAMPLE_TEXTS:
    tokenizer.encode(text)

# Run benchmark
print("\nBenchmarking", len(SAMPLE_TEXTS), "texts x", iterations, "iterations...")

total_tokens = 0
start = time.time()

i = 0
while i < iterations:
    for text in SAMPLE_TEXTS:
        tokens = tokenizer.encode(text)
        total_tokens = total_tokens + len(tokens)
    i = i + 1

elapsed = time.time() - start

print("Time:", elapsed, "s")
print("Total tokens:", total_tokens)
print("\n" + "=" * 50)
print("Done!")
print("=" * 50)
