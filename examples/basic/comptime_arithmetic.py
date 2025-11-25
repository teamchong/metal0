# Test comptime arithmetic evaluation
# These constant expressions should be evaluated at compile time

x = 2 + 3
y = 10 * 5
z = 100 / 4
w = 17 % 5
a = 2 ** 8
b = 10 - 3
c = 20 // 3

print(x)  # Should print: 5
print(y)  # Should print: 50
print(z)  # Should print: 25.0
print(w)  # Should print: 2
print(a)  # Should print: 256
print(b)  # Should print: 7
print(c)  # Should print: 6
