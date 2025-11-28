"""Arithmetic operations tests for metal0"""
import unittest

class TestIntegerArithmetic(unittest.TestCase):
    def test_addition(self):
        self.assertEqual(2 + 3, 5)

    def test_subtraction(self):
        self.assertEqual(10 - 4, 6)

    def test_multiplication(self):
        self.assertEqual(7 * 8, 56)

    def test_division(self):
        self.assertEqual(15 / 3, 5.0)

    def test_floor_division(self):
        self.assertEqual(17 // 5, 3)

    def test_modulo(self):
        self.assertEqual(17 % 5, 2)

    def test_power(self):
        self.assertEqual(2 ** 10, 1024)

    def test_negative(self):
        self.assertEqual(-5 + 3, -2)

    def test_compound_expression(self):
        self.assertEqual(2 + 3 * 4, 14)

    def test_parentheses(self):
        self.assertEqual((2 + 3) * 4, 20)

class TestFloatArithmetic(unittest.TestCase):
    def test_addition(self):
        self.assertAlmostEqual(1.5 + 2.5, 4.0)

    def test_subtraction(self):
        self.assertAlmostEqual(5.5 - 2.3, 3.2)

    def test_multiplication(self):
        self.assertAlmostEqual(2.5 * 4.0, 10.0)

    def test_division(self):
        self.assertAlmostEqual(7.5 / 2.5, 3.0)

class TestAugmentedAssignment(unittest.TestCase):
    def test_iadd(self):
        x = 5
        x += 3
        self.assertEqual(x, 8)

    def test_isub(self):
        x = 10
        x -= 4
        self.assertEqual(x, 6)

    def test_imul(self):
        x = 3
        x *= 4
        self.assertEqual(x, 12)

    def test_idiv(self):
        x = 20.0
        x /= 4
        self.assertEqual(x, 5.0)

    def test_ifloordiv(self):
        x = 17
        x //= 5
        self.assertEqual(x, 3)

    def test_imod(self):
        x = 17
        x %= 5
        self.assertEqual(x, 2)

class TestBitwise(unittest.TestCase):
    def test_and(self):
        self.assertEqual(0b1100 & 0b1010, 0b1000)

    def test_or(self):
        self.assertEqual(0b1100 | 0b1010, 0b1110)

    def test_xor(self):
        self.assertEqual(0b1100 ^ 0b1010, 0b0110)

    def test_not(self):
        self.assertEqual(~0, -1)

    def test_left_shift(self):
        self.assertEqual(1 << 4, 16)

    def test_right_shift(self):
        self.assertEqual(16 >> 2, 4)

class TestComparisons(unittest.TestCase):
    def test_equal(self):
        self.assertTrue(5 == 5)
        self.assertFalse(5 == 6)

    def test_not_equal(self):
        self.assertTrue(5 != 6)
        self.assertFalse(5 != 5)

    def test_less_than(self):
        self.assertTrue(3 < 5)
        self.assertFalse(5 < 3)

    def test_less_equal(self):
        self.assertTrue(3 <= 5)
        self.assertTrue(5 <= 5)
        self.assertFalse(6 <= 5)

    def test_greater_than(self):
        self.assertTrue(5 > 3)
        self.assertFalse(3 > 5)

    def test_greater_equal(self):
        self.assertTrue(5 >= 3)
        self.assertTrue(5 >= 5)
        self.assertFalse(3 >= 5)

class TestBooleanLogic(unittest.TestCase):
    def test_and(self):
        self.assertTrue(True and True)
        self.assertFalse(True and False)
        self.assertFalse(False and True)
        self.assertFalse(False and False)

    def test_or(self):
        self.assertTrue(True or True)
        self.assertTrue(True or False)
        self.assertTrue(False or True)
        self.assertFalse(False or False)

    def test_not(self):
        self.assertFalse(not True)
        self.assertTrue(not False)

if __name__ == "__main__":
    unittest.main()
