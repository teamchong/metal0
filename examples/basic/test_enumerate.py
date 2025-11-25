"""
Comprehensive test suite for enumerate() built-in function.

Tests cover:
- Basic enumerate with strings
- Enumerate with integers
- Enumerate in nested loops
- Using index in computations
- Multiple enumerate patterns
"""

# Test 1: Basic enumerate with strings
print("Test 1: Basic enumerate with strings")
items = ['apple', 'banana', 'cherry']
for i, fruit in enumerate(items):
    print(i, fruit)

# Test 2: Enumerate with integers
print("Test 2: Enumerate with integers")
for idx, num in enumerate([10, 20, 30, 40]):
    print(idx, num)

# Test 3: Enumerate in nested loop
print("Test 3: Enumerate in nested loop")
for i, x in enumerate([1, 2]):
    for j, y in enumerate([10, 20]):
        print(i, j, x, y)

# Test 4: Use index in computation
print("Test 4: Use index in computation")
total = 0
for i, val in enumerate([5, 10, 15]):
    total = total + (i * val)
print(total)

# Test 5: Enumerate with booleans
print("Test 5: Enumerate with booleans")
for idx, flag in enumerate([True, False, True]):
    print(idx, flag)

# Test 6: Multiple sequential enumerates
print("Test 6: Multiple sequential enumerates")
for i, x in enumerate([100, 200]):
    print(i, x)
for j, y in enumerate([300, 400]):
    print(j, y)

# Test 7: Enumerate with computation in loop body
print("Test 7: Enumerate with computation in loop body")
for idx, num in enumerate([2, 4, 6]):
    result = idx + num
    print(idx, num, result)

# Test 8: Enumerate collecting results
print("Test 8: Enumerate collecting results")
sum_indices = 0
sum_values = 0
for i, val in enumerate([10, 20, 30]):
    sum_indices = sum_indices + i
    sum_values = sum_values + val
print(sum_indices, sum_values)
