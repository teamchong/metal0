def test_basic_closure():
    """Test closure with single captured variable"""
    def outer(x: int) -> int:
        def inner(y: int) -> int:
            return x + y
        return inner(5)

    result = outer(10)
    assert result == 15, f"Expected 15, got {result}"

def test_multiple_captures():
    """Test closure with multiple captured variables"""
    def outer(x: int, y: int) -> int:
        def inner(z: int) -> int:
            return x + y + z
        return inner(5)

    result = outer(10, 20)
    assert result == 35, f"Expected 35, got {result}"

def test_nested_levels():
    """Test multiple nesting levels"""
    def level1(a: int) -> int:
        def level2(b: int) -> int:
            def level3(c: int) -> int:
                return a + b + c
            return level3(3)
        return level2(2)

    result = level1(1)
    assert result == 6, f"Expected 6, got {result}"

if __name__ == "__main__":
    test_basic_closure()
    print("✓ test_basic_closure passed")

    test_multiple_captures()
    print("✓ test_multiple_captures passed")

    test_nested_levels()
    print("✓ test_nested_levels passed")

    print("\nAll basic closure tests passed!")
