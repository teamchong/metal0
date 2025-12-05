# Test program WITH eval - bytecode VM should be included
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

# Use eval to compute fib(10)
code = "fib(10)"
result = eval(code)
print(f"eval('fib(10)') = {result}")
