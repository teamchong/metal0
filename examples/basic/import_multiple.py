"""Multiple function calls from same module"""
import mymath

sum_result = mymath.add(10, 5)
product = mymath.multiply(4, 3)
combined = mymath.add(sum_result, product)

print(sum_result)
print(product)
print(combined)
