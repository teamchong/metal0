"""Test closures and nested functions"""

def test_basic_closure(x: int) -> int:
    """Basic closure with one captured variable"""
    def inner(y: int) -> int:
        return x + y
    return inner(5)

def test_multiple_captures(x: int, y: int) -> int:
    """Closure capturing multiple variables"""
    def inner(z: int) -> int:
        return x + y + z
    return inner(5)

def test_nested_no_capture(x: int) -> int:
    """Nested function without captures"""
    def inner(y: int) -> int:
        return y * 2
    return inner(x)

def test_closure_with_multiply(x: int) -> int:
    """Closure with multiplication"""
    def inner(y: int) -> int:
        return x * y
    return inner(3)

if __name__ == "__main__":
    result1 = test_basic_closure(10)
    assert result1 == 15
    print("test_basic_closure: PASS")

    result2 = test_multiple_captures(10, 20)
    assert result2 == 35
    print("test_multiple_captures: PASS")

    result3 = test_nested_no_capture(10)
    assert result3 == 20
    print("test_nested_no_capture: PASS")

    result4 = test_closure_with_multiply(4)
    assert result4 == 12
    print("test_closure_with_multiply: PASS")

    print("All closure tests passed!")
