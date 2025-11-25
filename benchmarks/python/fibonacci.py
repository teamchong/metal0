def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

# Benchmark with fibonacci(45) - ensures ~60 seconds runtime on CPython
result = fibonacci(45)
print(result)
