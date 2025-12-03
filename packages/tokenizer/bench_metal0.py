# metal0 tokenizer benchmark
# Apple-to-apple comparison with tiktoken, rs-bpe, HuggingFace
from metal0 import tokenizer
import time
import json

# Init tokenizer
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Load benchmark data using json.load
f = open("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/benchmark_data.json", "r")
data = json.load(f)
f.close()

texts = data["texts"]

# Warmup (5 iterations)
i = 0
while i < 5:
    for t in texts:
        tokenizer.encode(t)
    i = i + 1

# Benchmark: 100 iterations (same as tiktoken)
start = time.time()
i = 0
while i < 100:
    for t in texts:
        tokenizer.encode(t)
    i = i + 1

elapsed_ms = (time.time() - start) * 1000
print(elapsed_ms, "ms")
