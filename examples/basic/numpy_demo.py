# NumPy + BLAS Demo - Full working implementation

import numpy

print("PyAOT NumPy Demo - Direct BLAS Integration")

# Create arrays
a = numpy.array([1.0, 2.0, 3.0])
b = numpy.array([4.0, 5.0, 6.0])
print("Created arrays a and b")

# Dot product using BLAS cblas_ddot
result = numpy.dot(a, b)
print("Dot product:", result)

# Sum
total = numpy.sum(a)
print("Sum:", total)

# Mean
avg = numpy.mean(a)
print("Mean:", avg)

print("All operations use direct BLAS calls!")
