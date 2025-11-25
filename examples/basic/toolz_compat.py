"""Test toolz compatibility patterns"""

# Pattern 1: identity
def identity(x):
    return x

print("identity:", identity(5))

# Pattern 2: compose (simplified)
def compose(f, g):
    return lambda x: f(g(x))

double = lambda x: x * 2
inc = lambda x: x + 1
f = compose(double, inc)
print("compose:", f(5))

# Pattern 3: curry (simplified - no decorator)
def curry2(f):
    """Curry a 2-arg function"""
    return lambda x: lambda y: f(x, y)

add = lambda a, b: a + b
add5 = curry2(add)(5)
print("curry:", add5(3))

# Pattern 4: pipe (apply functions in sequence)
def pipe(data, *funcs):
    result = data
    for f in funcs:
        result = f(result)
    return result

print("pipe:", pipe(5, inc, double))

print("\ntoolz patterns working!")
