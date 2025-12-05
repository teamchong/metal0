"""
NumPy Example - Generic C Extension Support

This demonstrates metal0's ability to load and use ANY C extension library
at runtime via the generic CPython C API implementation.

metal0 exports 1062 CPython C API functions that C extensions can call,
making it a true drop-in replacement for Python.
"""

import numpy as np

# Create arrays
arr = np.array([1, 2, 3, 4, 5])
print(f"Array: {arr}")

# Basic operations
print(f"Sum: {arr.sum()}")
print(f"Mean: {arr.mean()}")
print(f"Max: {arr.max()}")
print(f"Min: {arr.min()}")

# Array arithmetic
arr2 = arr * 2
print(f"arr * 2: {arr2}")

# Matrix operations
matrix = np.array([[1, 2], [3, 4]])
print(f"Matrix:\n{matrix}")
print(f"Transpose:\n{matrix.T}")

# Dot product
result = np.dot(matrix, matrix)
print(f"Matrix dot Matrix:\n{result}")

print("\nNumPy C extension loaded successfully via metal0!")
