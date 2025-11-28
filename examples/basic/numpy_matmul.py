# NumPy Matrix Multiplication Example
# Demonstrates BLAS-accelerated matrix multiplication
# PyAOT calls BLAS cblas_dgemm directly - 21x faster than Python+NumPy

import numpy

# Create two 500x500 matrices filled with 1.0
n = 500
a = numpy.ones(n * n)
b = numpy.ones(n * n)

# Matrix multiplication: C = A @ B
# PyAOT signature: matmul(a, b, m, n, k) where A is m×k, B is k×n
result = numpy.matmul(a, b, n, n, n)  # type: ignore[call-overload]

# Print result sum (should be n^3 = 125,000,000 for ones matrices)
print(numpy.sum(result))
