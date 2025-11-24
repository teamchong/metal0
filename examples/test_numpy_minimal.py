# Minimal NumPy test - just import and create array
import numpy as np

# Most basic operation - create array
arr = np.array([1, 2, 3])
print(arr)

# Test basic attribute access
print(arr.shape)
print(arr.dtype)

# Test basic arithmetic
arr2 = arr + 1
print(arr2)

print("NumPy basic test complete!")
