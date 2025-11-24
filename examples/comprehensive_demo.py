"""
PyAOT Comprehensive Feature Demo
Showcases all currently supported Python features
"""

print("=== PyAOT Feature Demonstration ===")
print("")

# 1. Basic Types
print("1. Basic Types")
x = 42
s = "Hello"
pi = 3.14
flag = True
print(x)
print(s)
print(pi)
print(flag)
print("")

# 2. Lists
print("2. Lists")
numbers = [1, 2, 3, 4, 5]
print(numbers)
print(len(numbers))
print("")

# 3. Functions with Type Annotations
print("3. Functions")

def add(a: int, b: int) -> int:
    return a + b

def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result1 = add(5, 3)
result2 = fibonacci(10)
print(result1)
print(result2)
print("")

# 4. Classes
print("4. Classes and Methods")

class Point:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

    def sum(self) -> int:
        return self.x + self.y

p = Point(3, 4)
print(p.x)
print(p.y)
print(p.sum())
print("")

# 5. List Comprehensions
print("5. List Comprehensions")
squares = [i * i for i in range(5)]
evens = [n for n in numbers if n % 2 == 0]
print(squares)
print(evens)
print("")

# 6. Control Flow - For Loop
print("6. For Loop")
for i in range(3):
    print(i)
print("")

# 7. While Loop
print("7. While Loop")
count = 0
while count < 3:
    print(count)
    count = count + 1
print("")

# 8. If/Else
print("8. If/Else")
if x > 40:
    print("x is greater than 40")
else:
    print("x is not greater than 40")
print("")

# 9. Operators
print("9. Operators")
a = 10
b = 3
print(a + b)
print(a - b)
print(a * b)
print(a ** 2)
print(a > b)
print(a == b)
print("")

# 10. Boolean Logic
print("10. Boolean Logic")
print(True and False)
print(True or False)
print(not True)
print("")

# 11. List Methods
print("11. List Methods")
test_list = [1, 2, 3]
test_list.append(4)
print(test_list)
print("")

# 12. Class Inheritance
print("12. Class Inheritance")

class Animal:
    def __init__(self, name: str):
        self.name = name

    def speak(self) -> str:
        return "sound"

class Dog(Animal):
    def speak(self) -> str:
        return "Woof!"

dog = Dog("Buddy")
print(dog.name)
print(dog.speak())
print("")

# Summary
print("=== Summary ===")
print("All core PyAOT features working!")
print("Compiles to native binary with zero Python runtime")
