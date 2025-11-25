# Dict benchmark - PyAOT vs Python
def benchmark():
    # Create dict (int values only for type consistency)
    data = {"iterations": 1000000, "multiplier": 1}

    # Access values
    total = 0
    i = 0
    while i < 1000:
        total = total + data["iterations"]
        i = i + 1

    print(total)

benchmark()
