"""
String concatenation benchmark
Tests: a + b + c + d (simple concatenation chain)
Run in tight loop for ~60 seconds on Python
"""

a = "Hello"
b = "World"
c = "PyAOT"
d = "Compiler"

# Run 650M iterations for ~60 seconds on CPython
result = ""
for i in range(650000000):
    result = a + b + c + d

print(result)
