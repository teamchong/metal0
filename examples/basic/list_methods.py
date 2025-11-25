# Test list methods
numbers = [1, 2, 3, 4, 5]

# Test count
count_of_3 = numbers.count(3)
print("Count of 3:")
print(count_of_3)

# Test index
index_of_4 = numbers.index(4)
print("Index of 4:")
print(index_of_4)

# Test extend
more = [6, 7, 8]
numbers.extend(more)
print("After extend, length:")
print(len(numbers))

# Test reverse
numbers.reverse()
print("After reverse, first element:")
print(numbers[0])

# Test remove
numbers.remove(8)
print("After remove(8), length:")
print(len(numbers))
