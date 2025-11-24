# Test 1: Annotation overrides inferred type
def get_value():
    return "string"

x: int = 42  # Direct value - should be int
y: str = "hello"  # String annotation with string value
z: int  # Annotation only - no value

# Test 2: Different annotation types
a: bool = True
b: float = 3.14

print(x, y, a, b)
