# Dict benchmark - PyAOT vs Python
def benchmark():
    # Create dict
    data = {"name": "benchmark", "iterations": 1000000, "enabled": 1}

    # Access values
    total = 0
    i = 0
    while i < 1000000:
        total = total + data["iterations"]
        i = i + 1

    print(total)

benchmark()
