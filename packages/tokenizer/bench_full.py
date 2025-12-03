# metal0 tokenizer benchmark - full dataset
from metal0 import tokenizer
import time
import json

# Init tokenizer
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Load benchmark data
f = open("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/benchmark_data.json", "r")
content = f.read()
f.close()

# Simple JSON parse - get texts array
# Format: {"texts": ["...", "...", ...]}
start_idx = content.find("[")
end_idx = content.rfind("]") + 1
texts_str = content[start_idx:end_idx]

# Parse texts manually (avoid json module)
texts = []
i = 1  # skip [
while i < len(texts_str) - 1:
    if texts_str[i] == '"':
        # Find end of string
        j = i + 1
        while j < len(texts_str):
            if texts_str[j] == '"' and texts_str[j-1] != '\\':
                break
            j = j + 1
        texts.append(texts_str[i+1:j])
        i = j + 1
    else:
        i = i + 1

print("Dataset:", len(texts), "texts x 100 iterations =", len(texts) * 100, "encodes")

# Warmup
for t in texts[:5]:
    tokenizer.encode(t)

# Benchmark
start = time.time()
i = 0
while i < 100:
    for t in texts:
        tokenizer.encode(t)
    i = i + 1

elapsed_ms = (time.time() - start) * 1000
print("metal0:", elapsed_ms, "ms")
