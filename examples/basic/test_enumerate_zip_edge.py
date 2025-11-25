"""
Edge case tests for enumerate() and zip() built-in functions.

Tests cover:
- Empty lists
- Single element lists
- Very long lists
- Mixed empty and non-empty
"""

# Test 1: Empty list enumerate
print("Test 1: Empty list enumerate")
for i, x in enumerate([]):
    print(i, x)
print("(no output expected)")

# Test 2: Single element enumerate
print("Test 2: Single element enumerate")
for i, x in enumerate([42]):
    print(i, x)

# Test 3: Empty zip
print("Test 3: Empty zip")
for x, y in zip([], []):
    print(x, y)
print("(no output expected)")

# Test 4: Single element zip
print("Test 4: Single element zip")
for x, y in zip([1], [10]):
    print(x, y)

# Test 5: Enumerate with many elements
print("Test 5: Enumerate with many elements")
count = 0
for i, val in enumerate([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]):
    count = count + 1
print(count)

# Test 6: Zip with many elements
print("Test 6: Zip with many elements")
count = 0
for x, y in zip([1, 2, 3, 4, 5], [10, 20, 30, 40, 50]):
    count = count + 1
print(count)

# Test 7: Enumerate after empty enumerate
print("Test 7: Enumerate after empty enumerate")
for i, x in enumerate([]):
    print(i, x)
for i, x in enumerate([100]):
    print(i, x)

# Test 8: Zip after empty zip
print("Test 8: Zip after empty zip")
for x, y in zip([], []):
    print(x, y)
for x, y in zip([1], [10]):
    print(x, y)

# Test 9: Nested enumerate with empty inner
print("Test 9: Nested enumerate with empty inner")
for i, x in enumerate([1, 2]):
    print(i, x)
    for j, y in enumerate([]):
        print(j, y)

# Test 10: Nested zip with empty inner
print("Test 10: Nested zip with empty inner")
for x, y in zip([1, 2], [10, 20]):
    print(x, y)
    for a, b in zip([], []):
        print(a, b)

# Test 11: Single element with computation
print("Test 11: Single element enumerate with computation")
total = 0
for i, val in enumerate([99]):
    total = total + (i * val)
print(total)

# Test 12: Single element zip with computation
print("Test 12: Single element zip with computation")
result = 0
for x, y in zip([5], [7]):
    result = x * y
print(result)
