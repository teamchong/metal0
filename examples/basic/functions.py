# Test function definitions

# Simple function with one parameter
def double(x):
    return x * 2

# Function with two parameters
def add(a, b):
    return a + b

# Function that calls another function
def quad(x):
    return double(double(x))

# Test the functions
print(double(5))
print(add(3, 7))
print(quad(3))
