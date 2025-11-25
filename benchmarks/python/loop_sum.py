# Sum numbers - 1.4 billion iterations for ~60 seconds on CPython
total = 0
for i in range(1400000000):
    total = total + i

print(total)
