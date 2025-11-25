# Simple function we can compile
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

def test_fibonacci_small():
    assert fibonacci(5) == 5
    assert fibonacci(10) == 55

def test_fibonacci_benchmark():
    # This is compute-intensive
    result = fibonacci(30)
    assert result == 832040

# Run tests
test_fibonacci_small()
print("test_fibonacci_small PASSED")

test_fibonacci_benchmark()
print("test_fibonacci_benchmark PASSED")
