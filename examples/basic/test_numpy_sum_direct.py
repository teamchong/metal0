# Test direct numpy function call mapping
import numpy as np

# Create a simple array (using list for now)
arr = [1.0, 2.0, 3.0]

# This should map to c.cblas_dasum() via C interop
# Note: For full support, need array type conversion
# For now, this tests the dispatch system
print("Array created:", arr)

# Uncomment when array conversion is ready:
# result = np.sum(arr)
# print("Sum:", result)
