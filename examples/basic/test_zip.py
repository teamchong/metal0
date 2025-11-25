"""
Comprehensive test suite for zip() built-in function.

Tests cover:
- Basic zip with 2 lists (various types)
- Zip with 3 lists
- Zip with different types (bools, ints, strings)
- Nested zip loops
- Computation with zipped values
- Multiple zip patterns
"""

# Test 1: Basic zip with 2 lists (integers and strings)
print("Test 1: Basic zip with 2 lists")
nums = [1, 2, 3]
letters = ['a', 'b', 'c']
for n, l in zip(nums, letters):
    print(n, l)

# Test 2: Zip with 3 lists
print("Test 2: Zip with 3 lists")
for x, y, z in zip([1, 2], [10, 20], [100, 200]):
    print(x, y, z)

# Test 3: Zip with different types (booleans and integers)
print("Test 3: Zip with booleans and integers")
bools = [True, False, True]
ints = [1, 2, 3]
for b, i in zip(bools, ints):
    print(b, i)

# Test 4: Nested zip
print("Test 4: Nested zip")
for a, b in zip([1, 2], [10, 20]):
    for c, d in zip([100, 200], [1000, 2000]):
        print(a, b, c, d)

# Test 5: Computation with zipped values
print("Test 5: Computation with zipped values")
result = 0
for x, y in zip([1, 2, 3], [10, 20, 30]):
    result = result + (x * y)
print(result)

# Test 6: Zip with strings
print("Test 6: Zip with strings")
fruits = ['apple', 'banana']
colors = ['red', 'yellow']
for f, c in zip(fruits, colors):
    print(f, c)

# Test 7: Multiple sequential zips
print("Test 7: Multiple sequential zips")
for x, y in zip([1, 2], [3, 4]):
    print(x, y)
for a, b in zip([5, 6], [7, 8]):
    print(a, b)

# Test 8: Zip with 4 lists
print("Test 8: Zip with 4 lists")
for a, b, c, d in zip([1, 2], [10, 20], [100, 200], [1000, 2000]):
    print(a, b, c, d)

# Test 9: Zip collecting multiple sums
print("Test 9: Zip collecting multiple sums")
sum_x = 0
sum_y = 0
for x, y in zip([1, 2, 3], [10, 20, 30]):
    sum_x = sum_x + x
    sum_y = sum_y + y
print(sum_x, sum_y)

# Test 10: Zip with computation in loop body
print("Test 10: Zip with computation in loop body")
for x, y in zip([2, 4, 6], [1, 2, 3]):
    product = x * y
    sum_val = x + y
    print(x, y, product, sum_val)
