# Test built-in numeric functions
# Note: These test the primitive versions that don't require runtime

# Test abs() - operates on primitives
neg_five = 0 - 5
print(abs(neg_five))
print(abs(10))
print(abs(0))

# Test min() with varargs - operates on primitives
print(min(5, 2, 8, 1))
print(min(10, 20))

# Test max() with varargs - operates on primitives
print(max(5, 2, 8, 1))
print(max(20, 10))
