import json
import time

# Benchmark JSON parsing in Python (baseline)
start = time.time()
for i in range(500000):
    obj = json.loads('{"value":42}')
    v = obj["value"]
elapsed = time.time() - start

print(f"Python: {elapsed:.3f}s ({500000/elapsed:.0f} ops/sec)")
