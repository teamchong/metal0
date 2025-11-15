# NumPy Demo - PyAOT calling NumPy via FFI

import numpy as np

print("Creating NumPy array...")
a = np.array([1, 2, 3, 4, 5])
print(a)

print("Computing sum...")
s = np.sum(a)
print(s)

print("Computing mean...")
m = np.mean(a)
print(m)

print("Computing min/max...")
min_val = np.min(a)
max_val = np.max(a)
print(min_val)
print(max_val)

print("NumPy FFI working!")
