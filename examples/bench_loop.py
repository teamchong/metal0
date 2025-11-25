# Benchmark: Loop with runtime-dependent values
# Uses list to prevent compile-time optimization
nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
total = 0
for _ in range(1000000):
    for n in nums:
        total = total + n
print(total)
