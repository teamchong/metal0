# NumPy Demo - Basic array operations

import numpy as np

# Array creation
a = np.array([1, 2, 3, 4, 5])
print("Array:", a)

# Array operations
doubled = a * 2
print("Doubled:", doubled)

# Dot product
dot = np.dot(a, a)
print("Dot product:", dot)

# Sum and mean
total = np.sum(a)
avg = np.mean(a)
print("Sum:", total)
print("Mean:", avg)
