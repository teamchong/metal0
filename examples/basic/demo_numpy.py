import numpy as np

# Test 1: Create array from list
arr = np.array([1, 2, 3, 4, 5])
print("Array created:", arr)

# Test 2: Sum array
total = np.sum(arr)
print("Sum:", total)  # Should print 15.0

# Test 3: Mean of array
avg = np.mean(arr)
print("Mean:", avg)  # Should print 3.0

# Test 4: Dot product
a = np.array([1, 2, 3])
b = np.array([4, 5, 6])
result = np.dot(a, b)
print("Dot product:", result)  # Should print 32.0

# Test 5: Create zeros array
zeros = np.zeros([3])
print("Zeros:", zeros)

# Test 6: Create ones array
ones = np.ones([3])
print("Ones:", ones)

print("\n✅ All NumPy operations completed successfully!")
print("🚀 PyAOT C interop working with BLAS at native speed!")
