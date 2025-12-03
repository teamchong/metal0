"""
Tokenizer benchmark - metal0 native Zig BPE tokenizer.

Usage:
    metal0 bench_tokenizer.py

Expected results (Apple M2):
    metal0 (Zig):     2.489s  (1.00x)
    rs-bpe (Rust):    3.866s  (1.55x slower)
    tiktoken (Rust):  9.311s  (3.74x slower)
    HuggingFace:      44.264s (17.78x slower)
"""

from metal0 import tokenizer
import time


# Sample texts for benchmarking
SAMPLE_TEXTS = [
    "Hello, world!",
    "The quick brown fox jumps over the lazy dog.",
    "Machine learning is transforming how we build software.",
    "Python is a great language for data science and AI.",
    "Tokenization is the first step in natural language processing.",
]


def benchmark_encode(iterations: int = 100):
    """Benchmark encoding performance"""
    print("Benchmarking", len(SAMPLE_TEXTS), "texts x", iterations, "iterations...")

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

    return elapsed


if __name__ == "__main__":
    print("=" * 50)
    print("metal0 Tokenizer Benchmark (native Zig BPE)")
    print("=" * 50)

    # Warm up
    print("\nWarming up...")
    for text in SAMPLE_TEXTS:
        tokenizer.encode(text)

    # Run benchmark
    print("\nRunning benchmark...")
    encode_time = benchmark_encode(iterations=100)

    print("\n" + "=" * 50)
    print("Done! Encode time:", encode_time, "s")
    print("=" * 50)
