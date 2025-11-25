"""Example using calculator module"""
import sys
sys.path.insert(0, "examples")

import calculator

result = calculator.add(10, 5)
sum_val = result

product = calculator.multiply(10, 5)
print("Sum:", sum_val)
print("Product:", product)
print("Calculator version:", calculator.VERSION)
