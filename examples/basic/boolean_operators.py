# Test and
x = 5
if x > 0 and x < 10:
    print("x is between 0 and 10")

# Test or
y = 15
if y < 0 or y > 10:
    print("y is out of range")

# Test not
flag = False
if not flag:
    print("flag is false")

# Test complex expressions
a = 3
b = 7
if (a > 0 and b > 0) or (a < 0 and b < 0):
    print("Both same sign")

# Test with comparisons
num = 8
if num > 5 and num < 15 and not num == 10:
    print("Complex condition true")
