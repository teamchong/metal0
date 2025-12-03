# metal0 tokenizer benchmark
# Apple-to-apple comparison with tiktoken
from metal0 import tokenizer
import time

# Init tokenizer
tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Sample texts (same as tiktoken benchmark)
texts = [
    "The quick brown fox jumps over the lazy dog.",
    "Hello world! Python is great for programming.",
    "Machine learning and artificial intelligence are transforming technology.",
]

# Warmup
for t in texts:
    tokenizer.encode(t)

# Benchmark: 30000 encodes (10000 iterations * 3 texts)
start = time.time()
i = 0
while i < 10000:
    for t in texts:
        tokenizer.encode(t)
    i = i + 1

elapsed_ms = (time.time() - start) * 1000
print(elapsed_ms, "ms for 30000 encodes")
