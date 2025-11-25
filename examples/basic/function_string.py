"""Function with string parameters and return"""

def greet(name: str) -> str:
    return "Hello, " + name

message = greet("World")
print(message)
