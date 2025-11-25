"""Comprehensive arithmetic tests adapted from Codon test suite"""


def test_basic_arithmetic():
    """Basic arithmetic operations"""
    assert 2 + 2 == 4
    assert 3.14 * 2 == 6.28
    assert 2 + 3*2 == 8
    assert 1.0/0 == float('inf')
    assert str(0.0/0) == 'nan'


def test_division_operators():
    """Integer and float division"""
    # Integer division
    assert 5 // 2 == 2
    assert 5 / 2 == 2.5

    # Float division
    assert 5.0 // 2.0 == 2
    assert 5.0 / 2.0 == 2.5

    # Mixed division
    assert 5 // 2.0 == 2
    assert 5 / 2.0 == 2.5
    assert 5.0 // 2 == 2
    assert 5.0 / 2 == 2.5


def test_conversions():
    """Type conversions between int, float, bool, str"""

    # int -> int, float, bool, str
    assert int(-42) == -42
    assert float(-42) == -42.0
    assert bool(0) == False
    assert bool(-1) == bool(1) == True
    assert str(-42) == '-42'

    # float -> int, float, bool, str
    assert int(-4.2) == -4
    assert int(4.2) == 4
    assert float(-4.2) == -4.2
    assert bool(0.0) == False
    assert bool(-0.1) == bool(0.1) == True
    assert str(-4.2) == '-4.2'

    # bool -> int, float, bool, str
    assert int(False) == 0
    assert int(True) == 1
    assert float(False) == 0.0
    assert float(True) == 1.0
    assert bool(False) == False
    assert bool(True) == True
    assert str(False) == 'False'
    assert str(True) == 'True'


def test_int_pow():
    """Integer power operations"""
    assert 3 ** 2 == 9
    assert 27 ** 7 == 10460353203
    assert (-27) ** 7 == -10460353203
    assert (-27) ** 6 == 387420489
    assert 1 ** 0 == 1
    assert 1 ** 1000 == 1
    assert 0 ** 3 == 0
    assert 0 ** 0 == 1


def test_float_operations():
    """Float arithmetic operations"""
    x = 5.5
    assert str(x) == '5.5'
    assert float(x) == x
    assert int(x) == 5
    assert float(x) == 5.5
    assert bool(x)
    assert not bool(0.0)

    # Unary operators
    assert +x == x
    assert -x == -5.5

    # Binary operators
    assert x + x == 11.0
    assert x - 1.0 == 4.5
    assert x * 3.0 == 16.5
    assert x / 2.0 == 2.75
    assert x // 2.0 == 2.0
    assert x % 0.75 == 0.25
    assert divmod(x, 0.75) == (7.0, 0.25)

    # Comparisons
    assert x == x
    assert x != 0.0
    assert x < 6.5
    assert x > 4.5
    assert x <= 6.5
    assert x >= 4.5
    assert x >= x
    assert x <= x

    # Absolute value
    assert abs(x) == x
    assert abs(-x) == x

    # Hash
    assert hash(x) == hash(5.5)


def test_int_float_ops():
    """Mixed int and float operations"""

    # Standard operations
    assert 1.5 + 1 == 2.5
    assert 1.5 - 1 == 0.5
    assert 1.5 * 2 == 3.0
    assert 1.5 / 2 == 0.75
    assert 3.5 // 2 == 1.0
    assert 3.5 % 2 == 1.5
    assert 3.5 ** 2 == 12.25
    assert divmod(3.5, 2) == (1.0, 1.5)

    # Right-hand operations
    assert 1 + 1.5 == 2.5
    assert 1 - 1.5 == -0.5
    assert 2 * 1.5 == 3.0
    assert 2 / 2.5 == 0.8
    assert 2 // 1.5 == 1.0
    assert 2 % 1.5 == 0.5
    assert 4 ** 2.5 == 32.0
    assert divmod(4, 2.5) == (1.0, 1.5)

    # Comparisons
    assert 1.0 == 1
    assert 2.0 != 1
    assert 0.0 < 1
    assert 2.0 > 1
    assert 0.0 <= 1
    assert 2.0 >= 1
    assert 1 == 1.0
    assert 1 != 2.0
    assert 1 < 2.0
    assert 1 > 0.0
    assert 1 <= 2.0
    assert 1 >= 0.0

    # Power operations
    assert 3.5 ** 1 == 3.5
    assert 3.5 ** 2 == 12.25
    assert 3.5 ** 3 == 42.875
    assert 4.0 ** -1 == 0.25
    assert 4.0 ** -2 == 0.0625
    assert 4.0 ** -3 == 0.015625
    assert 3.5 ** 0 == 1.0


def test_modulo_operations():
    """Modulo and divmod operations"""
    # Integer modulo
    assert 10 % 3 == 1
    assert 10 % -3 == -2
    assert -10 % 3 == 2
    assert -10 % -3 == -1

    # Float modulo
    assert 10.5 % 3.0 == 1.5
    assert 10.0 % 3.0 == 1.0

    # divmod
    assert divmod(10, 3) == (3, 1)
    assert divmod(10.5, 3.0) == (3.0, 1.5)


def test_subtraction():
    """Subtraction operations"""
    assert 10 - 5 == 5
    assert 5 - 10 == -5
    assert 10.5 - 5.5 == 5.0
    assert 10 - 5.5 == 4.5


def test_multiplication():
    """Multiplication operations"""
    assert 3 * 4 == 12
    assert 3.5 * 2 == 7.0
    assert 3 * 2.5 == 7.5
    assert -3 * 4 == -12
    assert -3 * -4 == 12


def test_edge_cases():
    """Edge cases and special values"""
    # Division by zero
    assert 1.0 / 0.0 == float('inf')
    assert -1.0 / 0.0 == float('-inf')

    # NaN
    nan_value = 0.0 / 0.0
    assert str(nan_value) == 'nan'

    # Very large numbers
    assert 999999999999 * 999999999999 == 999999999998000000000001

    # Very small floats
    assert 0.0000001 + 0.0000002 == 0.0000003
