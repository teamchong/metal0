# Test ALL Python print() cases for 100% spec compliance

# 1. Basic types
x: int = 42
name: str = "PyAOT"
pi: float = 3.14
flag: bool = True

# 2. Test individual prints
print(42)
print("hello")
print(3.14)
print(True)
print(False)

# 3. Test variables
print(x)
print(name)
print(pi)
print(flag)

# 4. Test multiple arguments
print(x, name)
print("x =", x)
print("Result:", x, "Name:", name)

# 5. Test empty print
print()

# 6. Test lists
nums = [1, 2, 3]
print(nums)
print([10, 20, 30])

# 7. Test mixed types in one print
print(x, name, pi, flag)
