# Simple demo showing Python syntax features now supported
# These are patterns commonly found in Flask and similar frameworks

# Numeric literals with underscores (PEP 515)
MAX_CONTENT_LENGTH = 16_000_000
TIMEOUT_MS = 500_000

# Chained assignment
x = y = z = 0
x = 1
y = 2

# Tuple assignment on right side
config = "debug", True

def greet(name: str) -> str:
    """Simple function with type annotations."""
    return f"Hello, {name}!"

print("Python syntax features demo:")
print(f"  MAX_CONTENT_LENGTH = {MAX_CONTENT_LENGTH}")
print(f"  TIMEOUT_MS = {TIMEOUT_MS}")
print(f"  x, y, z = {x}, {y}, {z}")
print(f"  config = {config}")
print(f"  greet('Flask') = {greet('Flask')}")
print("All syntax features work!")
