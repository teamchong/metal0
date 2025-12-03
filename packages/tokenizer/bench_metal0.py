# metal0 tokenizer benchmark
from metal0 import tokenizer
import time

# Init tokenizer (use absolute path)
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Single text for simple benchmark
text = "The quick brown fox jumps over the lazy dog. Hello world! Python is great."

# Warmup
result = tokenizer.encode(text)
result = tokenizer.encode(text)
result = tokenizer.encode(text)

# Benchmark: 59000 encodes (100 * 590 equivalent)
start = time.time()
for i in range(59000):
    result = tokenizer.encode(text)

elapsed_ms = (time.time() - start) * 1000
print(f"{elapsed_ms:.0f}ms")
