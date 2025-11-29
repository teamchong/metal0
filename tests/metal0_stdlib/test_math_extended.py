"""Extended math module tests for metal0"""
import math
import unittest

class TestMathConstants(unittest.TestCase):
    def test_pi_value(self):
        self.assertAlmostEqual(math.pi, 3.14159265359, places=5)

    def test_e_value(self):
        self.assertAlmostEqual(math.e, 2.71828182845, places=5)

class TestMathFunctions(unittest.TestCase):
    def test_sqrt_4(self):
        result = math.sqrt(4)
        self.assertEqual(result, 2.0)

    def test_sqrt_9(self):
        result = math.sqrt(9)
        self.assertEqual(result, 3.0)

    def test_sqrt_16(self):
        result = math.sqrt(16)
        self.assertEqual(result, 4.0)

    def test_pow_2_3(self):
        result = math.pow(2, 3)
        self.assertEqual(result, 8.0)

    def test_pow_3_2(self):
        result = math.pow(3, 2)
        self.assertEqual(result, 9.0)

    def test_abs_negative(self):
        result = math.fabs(-5)
        self.assertEqual(result, 5.0)

    def test_abs_positive(self):
        result = math.fabs(5)
        self.assertEqual(result, 5.0)

class TestMathFloorCeil(unittest.TestCase):
    def test_floor_positive(self):
        result = math.floor(3.7)
        self.assertEqual(result, 3.0)

    def test_floor_negative(self):
        result = math.floor(-3.7)
        self.assertEqual(result, -4.0)

    def test_ceil_positive(self):
        result = math.ceil(3.2)
        self.assertEqual(result, 4.0)

    def test_ceil_negative(self):
        result = math.ceil(-3.2)
        self.assertEqual(result, -3.0)

class TestMathTrig(unittest.TestCase):
    def test_sin_0(self):
        result = math.sin(0)
        self.assertAlmostEqual(result, 0.0, places=5)

    def test_cos_0(self):
        result = math.cos(0)
        self.assertAlmostEqual(result, 1.0, places=5)

    def test_tan_0(self):
        result = math.tan(0)
        self.assertAlmostEqual(result, 0.0, places=5)

if __name__ == "__main__":
    unittest.main()
