# Comprehensive builtin function tests (adapted from Codon)

def test_min_max_basic():
    # Basic min/max with two arguments
    assert min(42, 24) == 24
    assert max(42, 24) == 42

    # Min/max with lists
    assert min([42, 24]) == 24
    assert max([42, 24]) == 42

    # Min/max with multiple arguments
    assert min(1, 2, 3, 2, 1, 0, -1, 1, 2) == -1
    assert max(1, 2, 3, 2, 1, 0, -1, 1, 2) == 3

    # Min/max with list of multiple values
    assert min([1, 2, 3, 2, 1, 0, -1, 1, 2]) == -1
    assert max([1, 2, 3, 2, 1, 0, -1, 1, 2]) == 3

def test_min_max_strings():
    # String comparisons
    assert min('abcx') == 'a'
    assert max('abcx') == 'x'
    assert min(['a', 'b', 'c', 'x']) == 'a'
    assert max(['a', 'b', 'c', 'x']) == 'x'

def test_min_max_empty():
    # Test empty sequences raise ValueError
    try:
        max('')
        assert False
    except ValueError as e:
        assert 'empty' in str(e).lower()

    try:
        min('')
        assert False
    except ValueError as e:
        assert 'empty' in str(e).lower()

def test_sum():
    # Basic sum
    assert sum([1, 2, 3]) == 6
    assert sum([1, 2, 3], 0.5) == 6.5
    assert sum([]) == 0

def test_all_any():
    # all() tests
    assert all([True, True])
    assert not all([True, False])
    assert all([])

    # any() tests
    assert any([True, True])
    assert not any([False, False])
    assert not any([])

def test_map():
    # Basic map
    def add_one(i: int) -> int:
        return i + 1
    assert list(map(add_one, [0, 2, 4, 6, 8])) == [1, 3, 5, 7, 9]
    assert list(map(add_one, [])) == []

def test_filter():
    # Basic filter
    def is_even(i: int) -> bool:
        return i % 2 == 0
    def is_odd(i: int) -> bool:
        return i % 2 == 1
    assert list(filter(is_even, range(5))) == [0, 2, 4]
    assert list(filter(is_odd, [])) == []

def test_len():
    # len() with various types
    assert len([1, 2, 3]) == 3
    assert len("hello") == 5
    assert len([]) == 0
    assert len("") == 0
    assert len([1, 2, 3, 4, 5]) == 5

def test_str():
    # str() conversions
    assert str(42) == "42"
    assert str(-42) == "-42"
    assert str(3.14) == "3.14"
    assert str(True) == "True"
    assert str(False) == "False"

def test_int():
    # int() conversions
    assert int("42") == 42
    assert int("-42") == -42
    assert int(3.14) == 3
    assert int(True) == 1
    assert int(False) == 0

def test_int_from_str():
    # int() from string with base
    assert int('0') == 0
    assert int('010') == 10
    assert int('42') == 42
    assert int('0101', 2) == 5
    assert int('-0101', 2) == -5
    assert int('0111', 8) == 73
    assert int('-0111', 8) == -73
    assert int('0xabc', 16) == 2748
    assert int('-0xabc', 16) == -2748

    # Auto-detect base (base=0)
    assert int('111', 0) == 111
    assert int('-111', 0) == -111
    assert int('0xabc', 0) == 2748
    assert int('-0xabc', 0) == -2748

def test_float():
    # float() conversions
    assert float("3.14") == 3.14
    assert float("-3.14") == -3.14
    assert float(42) == 42.0
    assert float("0") == 0.0

def test_bool():
    # bool() conversions
    assert bool(1) == True
    assert bool(0) == False
    assert bool("hello") == True
    assert bool("") == False
    assert bool([1, 2]) == True
    assert bool([]) == False

def test_range():
    # range() basic
    assert list(range(5)) == [0, 1, 2, 3, 4]
    assert list(range(2, 5)) == [2, 3, 4]
    assert list(range(0, 10, 2)) == [0, 2, 4, 6, 8]
    assert list(range(5, 0, -1)) == [5, 4, 3, 2, 1]

def test_enumerate():
    # enumerate() basic
    result = list(enumerate(['a', 'b', 'c']))
    assert result == [(0, 'a'), (1, 'b'), (2, 'c')]

    result = list(enumerate(['x', 'y'], 10))
    assert result == [(10, 'x'), (11, 'y')]

def test_zip():
    # zip() basic
    result = list(zip([1, 2, 3], ['a', 'b', 'c']))
    assert result == [(1, 'a'), (2, 'b'), (3, 'c')]

    # Uneven lengths
    result = list(zip([1, 2], ['a', 'b', 'c']))
    assert result == [(1, 'a'), (2, 'b')]

def test_abs():
    # abs() for integers and floats
    assert abs(42) == 42
    assert abs(-42) == 42
    assert abs(3.14) == 3.14
    assert abs(-3.14) == 3.14
    assert abs(0) == 0

def test_pow():
    # pow() basic
    assert pow(3, 4) == 81
    assert pow(-3, 3) == -27
    assert pow(1, 0) == 1
    assert pow(-1, 0) == 1
    assert pow(0, 0) == 1

    # pow() with modulo
    assert pow(12, 12, 42) == 36
    assert pow(1234, 4321, 99) == 46

    # Float exponents
    assert pow(1.5, 2) == 2.25
    assert pow(9, 0.5) == 3.0

def test_round():
    # round() basic
    assert round(3.14) == 3
    assert round(3.5) == 4
    assert round(3.14159, 2) == 3.14
    assert round(3.14159, 0) == 3.0

def test_divmod():
    # divmod() basic
    assert divmod(12, 7) == (1, 5)
    assert divmod(-12, 7) == (-2, 2)
    assert divmod(12, -7) == (-2, -2)
    assert divmod(-12, -7) == (1, -5)

def test_reversed():
    # reversed() basic
    assert list(reversed([1, 2, 3])) == [3, 2, 1]
    assert list(reversed('abc')) == ['c', 'b', 'a']
    assert list(reversed('')) == []

def test_sorted():
    # sorted() basic
    assert sorted([3, 1, 4, 1, 5]) == [1, 1, 3, 4, 5]
    assert sorted([]) == []
    assert sorted(['c', 'a', 'b']) == ['a', 'b', 'c']

def test_int_format():
    # bin(), oct(), hex()
    n = 0
    assert (str(n), bin(n), oct(n), hex(n)) == ('0', '0b0', '0o0', '0x0')

    n = -1
    assert (str(n), bin(n), oct(n), hex(n)) == ('-1', '-0b1', '-0o1', '-0x1')

    n = 12345
    assert (str(n), bin(n), oct(n), hex(n)) == ('12345', '0b11000000111001', '0o30071', '0x3039')

    n = -12345
    assert (str(n), bin(n), oct(n), hex(n)) == ('-12345', '-0b11000000111001', '-0o30071', '-0x3039')

def test_type():
    # type() basic
    assert type(42).__name__ == "int"
    assert type(3.14).__name__ == "float"
    assert type("hello").__name__ == "str"
    assert type(True).__name__ == "bool"
    assert type([]).__name__ == "list"

def test_isinstance():
    # isinstance() basic
    assert isinstance(42, int)
    assert isinstance(3.14, float)
    assert isinstance("hello", str)
    assert isinstance(True, bool)
    assert isinstance([], list)
    assert not isinstance(42, str)

def test_chr_ord():
    # chr() and ord()
    assert chr(65) == 'A'
    assert chr(97) == 'a'
    assert ord('A') == 65
    assert ord('a') == 97
    assert ord(chr(42)) == 42
