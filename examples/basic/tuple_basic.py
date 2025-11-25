# Tuple basics - creation, indexing, printing
t = (1, 2, 3)
print(t)
print(t[0])
print(t[1])
print(t[2])
print(len(t))

# Tuple unpacking
x, y, z = t
print(x)
print(y)
print(z)

# Multiple assignment with explicit tuple
coords = (10, 20)
a, b = coords
print(a)
print(b)

# Tuple iteration
for item in (1, 2, 3):
    print(item)
