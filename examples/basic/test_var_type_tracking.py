# Test variable type tracking
import testpkg

# Simple assignment
x = 42
print(x)  # Should work - direct literal

# Function call assignment
y = testpkg.main_func()
print(y)  # This is the bug - y inferred as unknown
