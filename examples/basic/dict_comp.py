# Basic dict comprehension
squares = {x: x*x for x in range(5)}
print(squares)

# With filter
evens = {x: x*2 for x in range(10) if x % 2 == 0}
print(evens)
