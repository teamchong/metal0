def benchmark():
    data = {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8}
    total = 0
    i = 0
    while i < 10000000:
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
