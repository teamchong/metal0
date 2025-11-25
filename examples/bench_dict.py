# Dict benchmark - lookup-heavy workload
# Tests repeated key access (current PyAOT limitation: static dicts only)
def benchmark():
    # Static dict with multiple keys
    data = {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8}

    # Heavy lookup workload - 1M iterations
    total = 0
    i = 0
    while i < 1000000:
        total = total + data["a"]
        total = total + data["b"]
        total = total + data["c"]
        total = total + data["d"]
        total = total + data["e"]
        total = total + data["f"]
        total = total + data["g"]
        total = total + data["h"]
        i = i + 1

    print(total)

benchmark()
