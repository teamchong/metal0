# Comprehensive String Type System Test
# Tests string literals, methods, concatenation, and print format specs

# Test 1: String literal type inference
x = "hello"
print("Test 1 - String literal:")
print(x)

# Test 2: String method type inference
y = x.upper()
print("Test 2 - String method upper():")
print(y)

# Test 3: String concatenation type inference
z = "Hello" + " " + "World"
print("Test 3 - String concatenation:")
print(z)

# Test 4: Multiple types in print (format spec test)
print("Test 4 - Mixed types:")
print("Text:", 42, 3.14, True)

# Test 5: String methods chain
result = "  hello  ".strip().upper()
print("Test 5 - Method chaining:")
print(result)

# Test 6: String slicing
text = "abcdef"
slice_result = text[1:4]
print("Test 6 - String slicing:")
print(slice_result)

# Test 7: String split
words = "one,two,three".split(",")
print("Test 7 - String split:")
print(len(words))

# Test 8: String replace
replaced = "hello world".replace("world", "python")
print("Test 8 - String replace:")
print(replaced)

# Test 9: String lower
lower = "CAPS".lower()
print("Test 9 - String lower:")
print(lower)

# Test 10: String formatting in loops
items = ["apple", "banana", "cherry"]
print("Test 10 - Strings in loops:")
for item in items:
    print(item)
