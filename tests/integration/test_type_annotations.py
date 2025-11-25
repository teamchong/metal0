# Test type annotation improvements

# Test 1: Simple type annotations
x: int = 42
y: str = "hello"
z: float = 3.14
print(x)
print(y)
print(z)

# Test 2: Generic list annotation (single type param)
numbers: list[int] = [1, 2, 3, 4, 5]
print(numbers[0])

# Test 3: Annotation with mutation
result: int = 10
result = result + 5
print(result)

# Test 4: Type inference from value (no annotation)
auto_int = 100
auto_str = "world"
print(auto_int)
print(auto_str)
