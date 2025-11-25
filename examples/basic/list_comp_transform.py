# Test list comprehension with transformation
numbers = [1, 2, 3, 4, 5]

# Transform: multiply by 2
doubled = [x * 2 for x in numbers]
print("Doubled length:")
print(len(doubled))
print("Doubled[0]:")
print(doubled[0])
print("Doubled[4]:")
print(doubled[4])
