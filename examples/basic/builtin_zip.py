# zip() - parallel iteration

# Zip two lists
numbers = [1, 2, 3]
letters = ["a", "b", "c"]
print("Zipping numbers and letters:")
for num, letter in zip(numbers, letters):
    print(num)
    print(letter)

# Zip three lists
first = [10, 20, 30]
second = ["x", "y", "z"]
third = [100, 200, 300]
print("Zipping three lists:")
for a, b, c in zip(first, second, third):
    print(a)
    print(b)
    print(c)

# Zip with different lengths (stops at shortest)
short = [1, 2]
long = ["a", "b", "c", "d"]
print("Zipping different lengths:")
for n, l in zip(short, long):
    print(n)
    print(l)
