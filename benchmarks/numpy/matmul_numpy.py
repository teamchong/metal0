import numpy as np

# Create two 500x500 matrices filled with 1.0 (same as PyAOT)
size = 500
a = np.ones((size, size))
b = np.ones((size, size))

# Matrix multiplication
result = np.dot(a, b)
print(np.sum(result))
