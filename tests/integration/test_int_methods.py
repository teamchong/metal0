# Int operation tests (from Codon stdlib)

# Test runner
passed = 0

def run(name):
    global passed
    passed += 1
    print(f"{name}: PASS")

def test_int_arithmetic():
    """Test basic int arithmetic operations"""
    assert 5 + 3 == 8
    assert 5 - 3 == 2
    assert 5 * 3 == 15
    assert 15 // 3 == 5
    assert 15 % 4 == 3
    assert 2 ** 3 == 8


def test_int_negative():
    """Test negative int operations"""
    assert -5 + 3 == -2
    assert -5 - 3 == -8
    assert -5 * 3 == -15
    assert -15 // 3 == -5
    assert -15 % 4 == 1
    assert -2 ** 3 == -8


def test_int_comparison():
    """Test int comparison operations"""
    assert 5 > 3
    assert 3 < 5
    assert 5 >= 5
    assert 5 <= 5
    assert 5 == 5
    assert 5 != 3


def test_int_bitwise_and():
    """Test int bitwise AND operation"""
    assert (0b1010 & 0b1100) == 0b1000
    assert (15 & 7) == 7
    assert (0xFF & 0x0F) == 0x0F


def test_int_bitwise_or():
    """Test int bitwise OR operation"""
    assert (0b1010 | 0b1100) == 0b1110
    assert (8 | 4) == 12
    assert (0xF0 | 0x0F) == 0xFF


def test_int_bitwise_xor():
    """Test int bitwise XOR operation"""
    assert (0b1010 ^ 0b1100) == 0b0110
    assert (12 ^ 10) == 6
    assert (0xFF ^ 0xFF) == 0


def test_int_bitwise_not():
    """Test int bitwise NOT operation"""
    assert ~0 == -1
    assert ~1 == -2
    assert ~-1 == 0


def test_int_left_shift():
    """Test int left shift operation"""
    assert (1 << 0) == 1
    assert (1 << 1) == 2
    assert (1 << 2) == 4
    assert (1 << 3) == 8
    assert (5 << 2) == 20


def test_int_right_shift():
    """Test int right shift operation"""
    assert (8 >> 0) == 8
    assert (8 >> 1) == 4
    assert (8 >> 2) == 2
    assert (8 >> 3) == 1
    assert (20 >> 2) == 5


def test_int_abs():
    """Test int abs() function"""
    assert abs(5) == 5
    assert abs(-5) == 5
    assert abs(0) == 0


def test_int_pow():
    """Test int pow() function"""
    assert pow(2, 3) == 8
    assert pow(3, 2) == 9
    assert pow(5, 0) == 1
    assert pow(2, 10) == 1024


def test_int_divmod():
    """Test int divmod() function"""
    assert divmod(10, 3) == (3, 1)
    assert divmod(17, 5) == (3, 2)
    assert divmod(20, 4) == (5, 0)


def test_int_bool():
    """Test int to bool conversion"""
    assert bool(1) == True
    assert bool(0) == False
    assert bool(-1) == True
    assert bool(100) == True


def test_int_zero_operations():
    """Test int operations with zero"""
    assert 0 + 5 == 5
    assert 0 * 5 == 0
    assert 0 - 5 == -5
    assert 0 ** 5 == 0
    assert 5 + 0 == 5
    assert 5 * 0 == 0


def test_int_large_numbers():
    """Test int operations with large numbers"""
    assert 1000000 + 2000000 == 3000000
    assert 1000000 * 1000 == 1000000000
    assert 2 ** 20 == 1048576


if __name__ == "__main__":
    test_int_arithmetic(); run("test_int_arithmetic")
    test_int_negative(); run("test_int_negative")
    test_int_comparison(); run("test_int_comparison")
    test_int_bitwise_and(); run("test_int_bitwise_and")
    test_int_bitwise_or(); run("test_int_bitwise_or")
    test_int_bitwise_xor(); run("test_int_bitwise_xor")
    test_int_bitwise_not(); run("test_int_bitwise_not")
    test_int_left_shift(); run("test_int_left_shift")
    test_int_right_shift(); run("test_int_right_shift")
    test_int_abs(); run("test_int_abs")
    test_int_pow(); run("test_int_pow")
    test_int_divmod(); run("test_int_divmod")
    test_int_bool(); run("test_int_bool")
    test_int_zero_operations(); run("test_int_zero_operations")
    test_int_large_numbers(); run("test_int_large_numbers")

    print(f"\nAll {passed} int tests passed!")
