# Test type inference improvements

# Test 1: list[str] - multiple element types
names: list[str] = ["alice", "bob", "charlie"]
print(names[0])

# Test 2: list[float]
prices: list[float] = [1.99, 2.50, 3.75]
print(prices[1])
