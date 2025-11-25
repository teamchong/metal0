# enumerate() - loop with index

# Enumerate over list of strings
items = ["apple", "banana", "cherry"]
print("Enumerating fruits:")
for i, item in enumerate(items):
    print(i)
    print(item)

# Enumerate over list of numbers
numbers = [10, 20, 30, 40]
print("Enumerating numbers:")
for idx, num in enumerate(numbers):
    print(idx)
    print(num)
