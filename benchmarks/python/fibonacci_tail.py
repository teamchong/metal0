def fib_tail(n: int, a: int, b: int) -> int:
    if n == 0:
        return a
    return fib_tail(n - 1, b, a + b)

result: int = 0
for _ in range(10000):
    result = fib_tail(10000, 0, 1)
print(result)
