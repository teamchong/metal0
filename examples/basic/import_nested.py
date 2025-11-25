"""Nested module function calls - result of one function passed to another"""
import mymath

result = mymath.multiply(mymath.add(3, 2), 4)
print(result)
