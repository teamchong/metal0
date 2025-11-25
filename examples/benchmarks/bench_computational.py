# Simple HTTP handler benchmark
def handler():
    return '{"message": "Hello, World!", "status": "ok"}'

# Benchmark: call 1M times
for i in range(1000000):
    handler()

print("Done")
