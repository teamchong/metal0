def make_adder(x):
    def add(y):
        return x + y
    return add(5)

result = make_adder(10)
# Verify the result is correct using assert
assert result == 15
