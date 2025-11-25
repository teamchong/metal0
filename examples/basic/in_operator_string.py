# Test 'in' operator with strings
message = "Hello, World!"

if "World" in message:
    print("Found World")

if "Python" in message:
    print("Found Python")
else:
    print("Python not found")

if "" in message:
    print("Empty string found")
