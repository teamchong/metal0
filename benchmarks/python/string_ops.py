"""
String slicing benchmark
Tests: string slicing in tight loop
"""

text = "Hello World PyAOT Compiler System"

# Run string slicing - billions of iterations for ~60 seconds on Python
count = 0
last = ""
for i in range(2000000000):
    last = text[0:5]
    count = count + 1

print(count)
print(last)
