"""Multiple functions calling each other"""

def add(a: int, b: int) -> int:
    return a + b

def multiply(a: int, b: int) -> int:
    return a * b

def calculate(x: int, y: int) -> int:
    sum_result = add(x, y)
    product = multiply(x, y)
    return add(sum_result, product)

result = calculate(3, 4)
print(result)
