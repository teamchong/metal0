def test_return_closure():
    """Test returning closure from function"""
    def make_adder(x: int):
        def adder(y: int) -> int:
            return x + y
        return adder

    add5 = make_adder(5)
    result = add5(10)
    assert result == 15, f"Expected 15, got {result}"

def test_multiple_closures():
    """Test creating multiple independent closures"""
    def make_multiplier(factor: int):
        def multiply(x: int) -> int:
            return x * factor
        return multiply

    times2 = make_multiplier(2)
    times3 = make_multiplier(3)

    assert times2(5) == 10, "times2(5) failed"
    assert times3(5) == 15, "times3(5) failed"

if __name__ == "__main__":
    test_return_closure()
    print("✓ test_return_closure passed")

    test_multiple_closures()
    print("✓ test_multiple_closures passed")

    print("\nAll return closure tests passed!")
