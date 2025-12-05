# Example Python module for browser WASM
# Compile with: metal0 build --target wasm-browser math.py

def add(a: int, b: int) -> int:
    """Add two integers."""
    return a + b

def multiply(x: int, y: int) -> int:
    """Multiply two integers."""
    return x * y

def square(n: int) -> int:
    """Square a number."""
    return n * n

def max_of(a: int, b: int) -> int:
    """Return the larger of two numbers."""
    if a > b:
        return a
    return b

def abs_val(n: int) -> int:
    """Return absolute value."""
    if n < 0:
        return -n
    return n
