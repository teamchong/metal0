# metal0 tokenizer benchmark
# Run from packages/tokenizer/ where benchmark_data.json exists
from metal0 import tokenizer
import time
import json

# Load benchmark data (run from packages/tokenizer/)
with open("benchmark_data.json", "r") as f:
    data = json.load(f)
    texts = data["texts"]

# Init tokenizer with cl100k_base vocab (base64 format)
tokenizer.init("dist/cl100k_base_full.json")

# Warmup
for t in texts[:5]:
    tokenizer.encode(t)

# Benchmark
start = time.time()
for _ in range(100):
    for t in texts:
        tokenizer.encode(t)

elapsed_ms = (time.time() - start) * 1000
print(f"{elapsed_ms:.0f}ms")
