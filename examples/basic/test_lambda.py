"""Comprehensive lambda expression tests"""

# Test 1: Simple lambda
print("Test 1: Simple lambda")
double = lambda x: x * 2
print(double(5))  # 10
print(double(10))  # 20

# Test 2: Multiple parameters
print("\nTest 2: Multiple parameters")
add = lambda a, b: a + b
print(add(3, 7))  # 10
print(add(100, 200))  # 300

# Test 3: Lambda with comparisons
print("\nTest 3: Lambda with comparisons")
is_positive = lambda x: x > 0
print(is_positive(5))   # True
print(is_positive(-3))  # False

# Test 4: Lambda in list comprehension
print("\nTest 4: Lambda in list comp")
square = lambda x: x * x
numbers = [1, 2, 3, 4, 5]
squares = [square(n) for n in numbers]
print(squares)  # [1, 4, 9, 16, 25]

# Test 5: Nested lambda calls
print("\nTest 5: Nested calls")
add_one = lambda x: x + 1
double = lambda x: x * 2
result = double(add_one(5))
print(result)  # 12

# Test 6: Lambda with strings
print("\nTest 6: Lambda with strings")
get_first = lambda s: s[0]
print(get_first("hello"))  # h
print(get_first("world"))  # w

# Test 7: Immediate lambda execution
print("\nTest 7: Immediate execution")
result = (lambda x: x * 3)(7)
print(result)  # 21

# Test 8: Lambda returning lambda (if closures work)
print("\nTest 8: Higher-order")
make_adder = lambda x: lambda y: x + y
add_five = make_adder(5)
print(add_five(3))  # 8 (requires closure support)

print("\nAll lambda tests completed!")
