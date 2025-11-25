# Basic NumPy test - demonstrates direct BLAS integration
# This compiles to native code calling BLAS directly

import numpy

print("=== NumPy + BLAS Integration Test ===")

# Test 1: Create arrays
a = numpy.array([1.0, 2.0, 3.0])
b = numpy.array([4.0, 5.0, 6.0])
print("Arrays created")

# Test 2: Dot product (BLAS cblas_ddot)
# Expected: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32.0
result = numpy.dot(a, b)
print("Dot product:", result)

# Test 3: Sum
# Expected: 1 + 2 + 3 = 6.0
total = numpy.sum(a)
print("Sum:", total)

# Test 4: Mean
# Expected: 6.0 / 3 = 2.0
avg = numpy.mean(a)
print("Mean:", avg)

print("=== All tests passed! ===")
