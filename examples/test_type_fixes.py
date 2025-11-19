# Test file for type conversion fixes (i64 → usize)
items = ["a", "b", "c"]

# Test 1: range() loop with indexing
print("Test 1: range() loop")
for i in range(len(items)):
    print(items[i])

# Test 2: enumerate with indexing
print("Test 2: enumerate() loop")
data = [10, 20, 30]
for i, value in enumerate(data):
    print(i, value)
    if i < len(data) - 1:
        print(data[i + 1])

# Test 3: Manual counter (still i64, but should work with auto-cast)
print("Test 3: Manual counter")
j = 0
while j < len(items):
    print(items[j])
    j = j + 1
