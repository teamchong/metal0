# Test list comprehension with filter
numbers = [1, 2, 3, 4, 5]

# Filter: only values > 2
filtered = [x for x in numbers if x > 2]
print("Filtered length:")
print(len(filtered))
print("Filtered[0]:")
print(filtered[0])
print("Filtered[2]:")
print(filtered[2])
