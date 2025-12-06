# Test typing.cast - the function we fixed

from typing import cast

# Test 1: Basic import
def test_imports():
    print("test_imports: PASS")

# Test 2: cast with int type
def test_cast_int():
    x = 42
    y = cast(int, x)
    assert y == 42
    print("test_cast_int: PASS")

# Test 3: cast with float type
def test_cast_float():
    x = 3.14
    y = cast(float, x)
    assert y == 3.14
    print("test_cast_float: PASS")

# Test 4: Variable annotation with int
def test_var_annotation_int():
    x: int = 42
    assert x == 42
    print("test_var_annotation_int: PASS")

# Test 5: Function with type hints
def typed_add(a: int, b: int) -> int:
    return a + b

def test_function_hints():
    result = typed_add(1, 2)
    assert result == 3
    print("test_function_hints: PASS")

# Test 6: Class with annotations
class Point:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

    def magnitude_squared(self) -> int:
        return self.x * self.x + self.y * self.y

def test_class_annotations():
    p = Point(3, 4)
    assert p.x == 3
    assert p.y == 4
    assert p.magnitude_squared() == 25
    print("test_class_annotations: PASS")

# Test 7: Nested cast
def test_nested_cast():
    x = 10
    y = cast(int, cast(int, x))
    assert y == 10
    print("test_nested_cast: PASS")

# Run all tests
test_imports()
test_cast_int()
test_cast_float()
test_var_annotation_int()
test_function_hints()
test_class_annotations()
test_nested_cast()

print("\n=== All 7 typing.cast tests passed! ===")
