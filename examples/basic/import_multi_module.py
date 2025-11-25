"""Import multiple modules"""
import mymath
import strutils

num = mymath.add(2, 3)
text = strutils.repeat("Hi", num)

print(num)
print(text)
