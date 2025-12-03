# metal0 benchmark - 592 texts x 100 iterations
from metal0 import tokenizer
import time

tokenizer.init("/Users/steven_chong/Downloads/repos/metal0/packages/tokenizer/dist/cl100k_base_full.json")

# Same 592 texts as benchmark_data.json (3 unique texts repeated)
texts = []
i = 0
while i < 592:
    texts.append("The quick brown fox jumps over the lazy dog.")
    i = i + 1
    if i < 592:
        texts.append("Hello world! Python is great for programming.")
        i = i + 1
    if i < 592:
        texts.append("Machine learning and artificial intelligence are transforming technology.")
        i = i + 1

# Warmup
for t in texts[:5]:
    tokenizer.encode(t)

# Benchmark
start = time.time()
j = 0
while j < 100:
    for t in texts:
        tokenizer.encode(t)
    j = j + 1

elapsed_ms = (time.time() - start) * 1000
print(elapsed_ms, "ms")
