def test(x: int) -> int:
    def inner(y: int) -> int:
        return x + y
    return inner(5)

print(test(10))
