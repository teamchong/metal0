def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

# Compute fibonacci(35) - takes ~1 second in Python
result = fibonacci(35)
print(result)
