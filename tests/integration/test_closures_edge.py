def test_closure_no_capture():
    """Test nested function without captures"""
    def outer():
        def inner() -> int:
            return 42
        return inner()

    result = outer()
    assert result == 42

def test_closure_string_capture():
    """Test capturing string variable"""
    def outer(s: str) -> str:
        def inner(suffix: str) -> str:
            return s + suffix
        return inner(" world")

    result = outer("hello")
    assert result == "hello world"

if __name__ == "__main__":
    test_closure_no_capture()
    print("✓ test_closure_no_capture passed")

    test_closure_string_capture()
    print("✓ test_closure_string_capture passed")

    print("\nAll edge case tests passed!")
