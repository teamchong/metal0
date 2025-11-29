"""Comprehensive operator module tests for metal0"""
import operator
import unittest

class TestOperatorArithmetic(unittest.TestCase):
    def test_add_integers(self):
        self.assertEqual(operator.add(2, 3), 5)

    def test_add_negative(self):
        self.assertEqual(operator.add(-2, 3), 1)

    def test_add_zero(self):
        self.assertEqual(operator.add(0, 5), 5)

    def test_mul_integers(self):
        self.assertEqual(operator.mul(3, 4), 12)

    def test_mul_zero(self):
        self.assertEqual(operator.mul(5, 0), 0)

    def test_mul_negative(self):
        self.assertEqual(operator.mul(-2, 3), -6)

    def test_truediv(self):
        self.assertEqual(operator.truediv(10, 2), 5.0)

    def test_floordiv(self):
        self.assertEqual(operator.floordiv(10, 3), 3)

    def test_mod(self):
        self.assertEqual(operator.mod(10, 3), 1)

    def test_neg(self):
        self.assertEqual(operator.neg(5), -5)

    def test_pos(self):
        self.assertEqual(operator.pos(5), 5)

    def test_abs(self):
        self.assertEqual(operator.abs(-5), 5)

class TestOperatorComparison(unittest.TestCase):
    def test_lt_true(self):
        self.assertTrue(operator.lt(1, 2))

    def test_lt_false(self):
        self.assertFalse(operator.lt(2, 1))

    def test_le_equal(self):
        self.assertTrue(operator.le(2, 2))

    def test_le_less(self):
        self.assertTrue(operator.le(1, 2))

    def test_eq_true(self):
        self.assertTrue(operator.eq(5, 5))

    def test_eq_false(self):
        self.assertFalse(operator.eq(5, 6))

    def test_ne_true(self):
        self.assertTrue(operator.ne(5, 6))

    def test_ne_false(self):
        self.assertFalse(operator.ne(5, 5))

    def test_gt_true(self):
        self.assertTrue(operator.gt(2, 1))

    def test_gt_false(self):
        self.assertFalse(operator.gt(1, 2))

    def test_ge_equal(self):
        self.assertTrue(operator.ge(2, 2))

    def test_ge_greater(self):
        self.assertTrue(operator.ge(3, 2))

class TestOperatorLogical(unittest.TestCase):
    def test_not_true(self):
        self.assertFalse(operator.not_(True))

    def test_not_false(self):
        self.assertTrue(operator.not_(False))

    def test_truth_true(self):
        self.assertTrue(operator.truth(1))

    def test_truth_false(self):
        self.assertFalse(operator.truth(0))

class TestOperatorBitwise(unittest.TestCase):
    def test_and(self):
        self.assertEqual(operator.and_(12, 10), 8)

    def test_or(self):
        self.assertEqual(operator.or_(12, 10), 14)

    def test_xor(self):
        self.assertEqual(operator.xor(12, 10), 6)

    def test_lshift(self):
        self.assertEqual(operator.lshift(1, 4), 16)

    def test_rshift(self):
        self.assertEqual(operator.rshift(16, 2), 4)

    def test_invert(self):
        # Note: invert(0) = -1, invert(1) = -2, etc.
        self.assertEqual(operator.invert(1), -2)

class TestOperatorPow(unittest.TestCase):
    def test_pow_2_3(self):
        self.assertEqual(operator.pow(2, 3), 8)

    def test_pow_10_0(self):
        self.assertEqual(operator.pow(10, 0), 1)

if __name__ == "__main__":
    unittest.main()
