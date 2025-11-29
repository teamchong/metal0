"""Comprehensive operator module tests for metal0"""
import operator
import unittest

class TestOperatorArithmetic(unittest.TestCase):
    def test_add(self):
        self.assertEqual(operator.add(2, 3), 5)

    def test_add_negative(self):
        self.assertEqual(operator.add(-2, 3), 1)

    def test_add_zero(self):
        self.assertEqual(operator.add(0, 0), 0)

    def test_mul(self):
        self.assertEqual(operator.mul(4, 3), 12)

    def test_mul_zero(self):
        self.assertEqual(operator.mul(4, 0), 0)

    def test_mul_negative(self):
        self.assertEqual(operator.mul(-4, 3), -12)

    def test_truediv(self):
        result = operator.truediv(10, 4)
        self.assertTrue(abs(result - 2.5) < 0.001)

    def test_floordiv(self):
        self.assertEqual(operator.floordiv(10, 3), 3)

    def test_floordiv_negative(self):
        self.assertEqual(operator.floordiv(-10, 3), -4)

    def test_mod(self):
        self.assertEqual(operator.mod(10, 3), 1)

    def test_mod_zero(self):
        self.assertEqual(operator.mod(9, 3), 0)

    def test_add_large(self):
        self.assertEqual(operator.add(1000, 2000), 3000)

    def test_mul_large(self):
        self.assertEqual(operator.mul(100, 100), 10000)

    def test_neg(self):
        self.assertEqual(operator.neg(5), -5)

    def test_neg_negative(self):
        self.assertEqual(operator.neg(-5), 5)

    def test_pos(self):
        self.assertEqual(operator.pos(5), 5)

    def test_abs(self):
        self.assertEqual(operator.abs(-5), 5)

    def test_abs_positive(self):
        self.assertEqual(operator.abs(5), 5)

class TestOperatorComparison(unittest.TestCase):
    def test_lt(self):
        self.assertTrue(operator.lt(2, 3))

    def test_lt_false(self):
        self.assertFalse(operator.lt(3, 2))

    def test_le(self):
        self.assertTrue(operator.le(2, 3))

    def test_le_equal(self):
        self.assertTrue(operator.le(3, 3))

    def test_eq(self):
        self.assertTrue(operator.eq(3, 3))

    def test_eq_false(self):
        self.assertFalse(operator.eq(2, 3))

    def test_ne(self):
        self.assertTrue(operator.ne(2, 3))

    def test_ne_false(self):
        self.assertFalse(operator.ne(3, 3))

    def test_ge(self):
        self.assertTrue(operator.ge(3, 2))

    def test_ge_equal(self):
        self.assertTrue(operator.ge(3, 3))

    def test_gt(self):
        self.assertTrue(operator.gt(3, 2))

    def test_gt_false(self):
        self.assertFalse(operator.gt(2, 3))

class TestOperatorBitwise(unittest.TestCase):
    def test_and_(self):
        self.assertEqual(operator.and_(5, 3), 1)

    def test_or_(self):
        self.assertEqual(operator.or_(5, 3), 7)

    def test_xor(self):
        self.assertEqual(operator.xor(5, 3), 6)

    def test_lshift(self):
        self.assertEqual(operator.lshift(1, 4), 16)

    def test_rshift(self):
        self.assertEqual(operator.rshift(16, 2), 4)

class TestOperatorLogical(unittest.TestCase):
    def test_not_(self):
        self.assertTrue(operator.not_(False))

    def test_not_true(self):
        self.assertFalse(operator.not_(True))

    def test_truth(self):
        self.assertTrue(operator.truth(1))

    def test_truth_zero(self):
        self.assertFalse(operator.truth(0))

if __name__ == "__main__":
    unittest.main()
