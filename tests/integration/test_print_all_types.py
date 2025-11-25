# Test print() with all supported types

def test_print_int():
    x: int = 42
    print(x)

def test_print_str():
    name: str = "hello"
    print(name)

def test_print_float():
    pi: float = 3.14
    print(pi)

def test_print_bool():
    flag: bool = True
    print(flag)
    flag2: bool = False
    print(flag2)

def test_print_list():
    nums = [1, 2, 3]
    print(nums)

def test_print_multiple():
    x: int = 42
    name: str = "world"
    print(x, name)

def test_print_mixed():
    x: int = 10
    y: float = 2.5
    name: str = "test"
    flag: bool = True
    print(x, y, name, flag)

def test_print_empty():
    print()
