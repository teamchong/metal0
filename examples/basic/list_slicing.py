# Test list slicing
numbers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

# Basic slicing
subset = numbers[2:5]  # [2, 3, 4]
print("Subset length:")
print(len(subset))
print("Subset[0]:")
print(subset[0])
print("Subset[1]:")
print(subset[1])

# Slice from start
first_three = numbers[:3]  # [0, 1, 2]
print("First 3 length:")
print(len(first_three))

# Slice to end
last_five = numbers[5:]  # [5, 6, 7, 8, 9]
print("Last 5 length:")
print(len(last_five))
