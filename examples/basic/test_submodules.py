import mylib

# Test main module
msg = mylib.hello()
print(msg)

# Test submodule access
text = mylib.utils.format_text("hello world")
print(text)

# Test another submodule
result = mylib.math_ops.square(5)
print(result)
