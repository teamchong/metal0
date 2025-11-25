# Simple NumPy sum example for C library mapping demo
# This will be compiled to direct BLAS calls (once codegen is integrated)

import numpy as np

# Create array
arr = [1.0, 2.0, 3.0, 4.0, 5.0]

# For now, use simple list sum since numpy.array() needs more work
# Later: arr = np.array([1.0, 2.0, 3.0, 4.0, 5.0])

# Compute sum (will map to cblas_dasum)
# Later: result = np.sum(arr)

# For now, manual sum
result = 0.0
for x in arr:
    result = result + x

print(result)
