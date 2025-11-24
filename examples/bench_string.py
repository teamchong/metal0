# String benchmark - PyAOT vs Python
def benchmark():
    result = ""
    i = 0
    while i < 10000:
        result = result + "x"
        i = i + 1
    print(len(result))

benchmark()
