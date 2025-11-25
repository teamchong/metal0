def fib(n: int) -> int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

# fib(45) ~3s for PyAOT/Rust/Go, ~100s for Python
# Long enough runtime that startup overhead is negligible
result = fib(45)
print(result)
