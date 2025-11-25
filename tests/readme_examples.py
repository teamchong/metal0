# tests/readme_examples.py
# Auto-extracted from README.md
# Verifies README code examples actually compile and run

# ============================================================
# Example 1: Basic greeting (README line 45-46)
# ============================================================
def greet(name: str) -> str:
    return f"Hello {name}!"

# ============================================================
# Example 2: Object-Oriented - Class Inheritance (README line 256-272)
# ============================================================
class Shape:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

class Rectangle(Shape):
    def __init__(self, x: int, y: int, width: int, height: int):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def area(self) -> int:
        return self.width * self.height

# ============================================================
# Example 3: List Processing (README line 280-288)
# ============================================================
def test_list_processing():
    numbers = [1, 2, 3, 4, 5]
    filtered = [x for x in numbers if x > 2]
    print(filtered)  # [3, 4, 5]

    # List methods
    numbers.append(6)
    numbers.reverse()
    print(numbers)

# ============================================================
# Example 4: String Operations (README line 295-300)
# ============================================================
def test_string_operations():
    text = "Hello, World!"
    upper = text.upper()
    words = text.split(", ")
    print(upper)     # HELLO, WORLD!
    print(words[0])  # Hello

# ============================================================
# Main - Run all examples
# ============================================================
if __name__ == "__main__":
    # Example 1: Basic greeting
    result = greet("World")
    print(result)  # Hello World!

    # Example 2: Class inheritance
    rect = Rectangle(10, 20, 5, 3)
    print(rect.area())  # 15

    # Example 3: List processing
    test_list_processing()

    # Example 4: String operations
    test_string_operations()

    print("All README examples passed!")
