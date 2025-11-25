# Test tail-call optimization
# fib_tail uses tail recursion: return fib_tail(n-1, b, a+b)
# This should compile to @call(.always_tail, ...) for ~9x speedup

def fib_tail(n: int, a: int, b: int) -> int:
    if n == 0:
        return a
    return fib_tail(n-1, b, a+b)  # IS tail-recursive

result = fib_tail(10, 0, 1)
print(result)  # Should print 55
