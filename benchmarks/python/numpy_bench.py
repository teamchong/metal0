# NumPy + PyAOT Benchmark
# Tests: NumPy import + array creation (realistic mixed workload)
# Compatible with: CPython, PyPy, Numba, PyAOT

import numpy as np

# Create NumPy arrays in loop - tests FFI overhead
# 32M iterations for ~60 seconds on Python
a = np.array([0])
b = np.array([0])
c = np.array([0])
d = np.array([0])

for i in range(32000000):
    a = np.array([1, 2, 3, 4, 5])
    b = np.array([10, 20, 30, 40, 50])
    c = np.array([100, 200, 300, 400, 500])
    d = np.array([1000, 2000, 3000, 4000, 5000])

# Print final results to verify correctness
print(a)
print(b)
print(c)
print(d)
