# Float operation tests (from Codon stdlib)

def test_float_arithmetic():
    """Test basic float arithmetic operations"""
    assert 5.5 + 3.2 == 8.7
    assert 5.5 - 3.2 == 2.3
    assert 2.0 * 3.0 == 6.0
    assert 6.0 / 3.0 == 2.0
    assert 7.0 // 3.0 == 2.0


def test_float_negative():
    """Test negative float operations"""
    assert -5.5 + 3.2 == -2.3
    assert -5.5 - 3.2 == -8.7
    assert -2.0 * 3.0 == -6.0
    assert -6.0 / 3.0 == -2.0


def test_float_comparison():
    """Test float comparison operations"""
    assert 5.5 > 3.2
    assert 3.2 < 5.5
    assert 5.0 >= 5.0
    assert 5.0 <= 5.0
    assert 5.0 == 5.0
    assert 5.0 != 3.0


def test_float_abs():
    """Test float abs() function"""
    assert abs(5.5) == 5.5
    assert abs(-5.5) == 5.5
    assert abs(0.0) == 0.0
    assert abs(-0.0) == 0.0


def test_float_round():
    """Test float round() function"""
    assert round(3.3) == 3
    assert round(3.5) == 4
    assert round(3.7) == 4
    assert round(-3.3) == -3
    assert round(-3.5) == -4
    assert round(-3.7) == -4


def test_float_bool():
    """Test float to bool conversion"""
    assert bool(1.0) == True
    assert bool(0.0) == False
    assert bool(-1.0) == True
    assert bool(0.5) == True


def test_float_zero_operations():
    """Test float operations with zero"""
    assert 0.0 + 5.5 == 5.5
    assert 0.0 * 5.5 == 0.0
    assert 0.0 - 5.5 == -5.5
    assert 5.5 + 0.0 == 5.5
    assert 5.5 * 0.0 == 0.0


def test_float_special_values():
    """Test float special values (inf, nan)"""
    inf = float('inf')
    ninf = float('-inf')
    nan = float('nan')

    # Test infinity
    assert inf > 0.0
    assert ninf < 0.0
    assert inf > ninf

    # Test NaN (NaN != NaN by IEEE 754)
    assert nan != nan


def test_float_mixed_operations():
    """Test float operations with int"""
    assert 5.5 + 3 == 8.5
    assert 5.5 - 3 == 2.5
    assert 2.5 * 4 == 10.0
    assert 10.0 / 2 == 5.0


def test_float_power():
    """Test float power operations"""
    assert 2.0 ** 3.0 == 8.0
    assert 4.0 ** 0.5 == 2.0
    assert 9.0 ** 0.5 == 3.0


def test_float_modulo():
    """Test float modulo operations"""
    assert 10.0 % 3.0 == 1.0
    assert 10.5 % 2.0 == 0.5
    assert 7.5 % 2.5 == 0.0
