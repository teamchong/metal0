"""
metal0 BPE training benchmark (Python → binary)

Trains BPE tokenizer 300 times on benchmark data.
Uses metal0.tokenizer.train() API.

Compile:
    metal0 build -b bench_train_metal0.py

Usage:
    ./bin/bench_train
"""

from metal0 import tokenizer
import json

# Load benchmark data
with open("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/benchmark_data.json") as f:
    data = json.load(f)
    texts = data["texts"]

VOCAB_SIZE = 32000
ITERATIONS = 300

print(f"BPE Training Benchmark: {len(texts)} texts x {ITERATIONS} iterations")
print(f"Vocab size: {VOCAB_SIZE}")
print()

# Train 300 times
i = 0
while i < ITERATIONS:
    tokenizer.train_bpe(texts, VOCAB_SIZE)
    i = i + 1

print(f"Completed {ITERATIONS} training iterations")
