# Simple function call benchmark for PyAOT
def handler():
    return 1

# Benchmark: call 100k times (reduced for print compatibility)
total = 0
for i in range(100000):
    total = total + handler()

print(total)
