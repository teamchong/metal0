def outer(a, b):
    def inner(c):
        return a + b + c
    return inner(100)

result1 = outer(10, 20)
assert result1 == 130

def make_multiplier(factor):
    def multiply(x):
        return x * factor
    return multiply(7)

result2 = make_multiplier(3)
assert result2 == 21
