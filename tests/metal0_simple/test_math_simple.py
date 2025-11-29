"""Comprehensive math module tests for metal0"""
import math
import unittest

class TestMathConstants(unittest.TestCase):
    def test_pi(self):
        self.assertTrue(abs(math.pi - 3.14159265) < 0.0001)

    def test_e(self):
        self.assertTrue(abs(math.e - 2.71828182) < 0.0001)

    def test_tau(self):
        self.assertTrue(abs(math.tau - 6.28318530) < 0.0001)

    def test_inf(self):
        self.assertTrue(math.inf > 1e308)

    def test_nan(self):
        self.assertTrue(math.isnan(math.nan))

class TestMathBasicOps(unittest.TestCase):
    def test_sqrt_4(self):
        self.assertEqual(math.sqrt(4), 2.0)

    def test_sqrt_9(self):
        self.assertEqual(math.sqrt(9), 3.0)

    def test_sqrt_16(self):
        self.assertEqual(math.sqrt(16), 4.0)

    def test_sqrt_2(self):
        self.assertAlmostEqual(math.sqrt(2), 1.41421356, places=5)

    def test_floor_positive(self):
        self.assertEqual(math.floor(3.7), 3)

    def test_floor_negative(self):
        self.assertEqual(math.floor(-3.7), -4)

    def test_ceil_positive(self):
        self.assertEqual(math.ceil(3.2), 4)

    def test_ceil_negative(self):
        self.assertEqual(math.ceil(-3.2), -3)

    def test_trunc_positive(self):
        self.assertEqual(math.trunc(3.7), 3)

    def test_trunc_negative(self):
        self.assertEqual(math.trunc(-3.7), -3)

    def test_fabs_negative(self):
        self.assertEqual(math.fabs(-5.5), 5.5)

    def test_fabs_positive(self):
        self.assertEqual(math.fabs(5.5), 5.5)

class TestMathPower(unittest.TestCase):
    def test_pow_2_3(self):
        self.assertEqual(math.pow(2, 3), 8.0)

    def test_pow_3_2(self):
        self.assertEqual(math.pow(3, 2), 9.0)

    def test_pow_2_10(self):
        self.assertEqual(math.pow(2, 10), 1024.0)

    def test_exp_0(self):
        self.assertEqual(math.exp(0), 1.0)

    def test_exp_1(self):
        self.assertAlmostEqual(math.exp(1), math.e, places=5)

    def test_exp2_3(self):
        self.assertEqual(math.exp2(3), 8.0)

    def test_exp2_10(self):
        self.assertEqual(math.exp2(10), 1024.0)

class TestMathLog(unittest.TestCase):
    def test_log_e(self):
        self.assertAlmostEqual(math.log(math.e), 1.0, places=5)

    def test_log_1(self):
        self.assertEqual(math.log(1), 0.0)

    def test_log10_100(self):
        self.assertEqual(math.log10(100), 2.0)

    def test_log10_1000(self):
        self.assertEqual(math.log10(1000), 3.0)

    def test_log2_8(self):
        self.assertEqual(math.log2(8), 3.0)

    def test_log2_1024(self):
        self.assertEqual(math.log2(1024), 10.0)

class TestMathTrig(unittest.TestCase):
    def test_sin_0(self):
        self.assertAlmostEqual(math.sin(0), 0.0, places=5)

    def test_cos_0(self):
        self.assertAlmostEqual(math.cos(0), 1.0, places=5)

    def test_tan_0(self):
        self.assertAlmostEqual(math.tan(0), 0.0, places=5)

    def test_sin_pi_2(self):
        self.assertAlmostEqual(math.sin(1.5707963267948966), 1.0, places=5)

    def test_cos_pi(self):
        self.assertAlmostEqual(math.cos(math.pi), -1.0, places=5)

    def test_asin_1(self):
        self.assertAlmostEqual(math.asin(1), 1.5707963267948966, places=5)

    def test_acos_0(self):
        self.assertAlmostEqual(math.acos(0), 1.5707963267948966, places=5)

    def test_atan_1(self):
        self.assertAlmostEqual(math.atan(1), 0.7853981633974483, places=5)

class TestMathHyperbolic(unittest.TestCase):
    def test_sinh_0(self):
        self.assertEqual(math.sinh(0), 0.0)

    def test_cosh_0(self):
        self.assertEqual(math.cosh(0), 1.0)

    def test_tanh_0(self):
        self.assertEqual(math.tanh(0), 0.0)

class TestMathSpecial(unittest.TestCase):
    def test_factorial_0(self):
        self.assertEqual(math.factorial(0), 1)

    def test_factorial_5(self):
        self.assertEqual(math.factorial(5), 120)

    def test_factorial_10(self):
        self.assertEqual(math.factorial(10), 3628800)

    def test_gcd_12_8(self):
        self.assertEqual(math.gcd(12, 8), 4)

    def test_gcd_100_25(self):
        self.assertEqual(math.gcd(100, 25), 25)

    def test_lcm_4_6(self):
        self.assertEqual(math.lcm(4, 6), 12)

    def test_lcm_3_5(self):
        self.assertEqual(math.lcm(3, 5), 15)

class TestMathClassification(unittest.TestCase):
    def test_isfinite_1(self):
        self.assertTrue(math.isfinite(1.0))

    def test_isfinite_inf(self):
        self.assertFalse(math.isfinite(math.inf))

    def test_isinf_inf(self):
        self.assertTrue(math.isinf(math.inf))

    def test_isinf_1(self):
        self.assertFalse(math.isinf(1.0))

    def test_isnan_nan(self):
        self.assertTrue(math.isnan(math.nan))

    def test_isnan_1(self):
        self.assertFalse(math.isnan(1.0))

class TestMathAngular(unittest.TestCase):
    def test_degrees_pi(self):
        self.assertAlmostEqual(math.degrees(math.pi), 180.0, places=5)

    def test_degrees_pi_2(self):
        self.assertAlmostEqual(math.degrees(1.5707963267948966), 90.0, places=5)

    def test_radians_180(self):
        self.assertAlmostEqual(math.radians(180), math.pi, places=5)

    def test_radians_90(self):
        self.assertAlmostEqual(math.radians(90), 1.5707963267948966, places=5)

class TestMathComb(unittest.TestCase):
    def test_comb_5_2(self):
        self.assertEqual(math.comb(5, 2), 10)

    def test_comb_10_3(self):
        self.assertEqual(math.comb(10, 3), 120)

    def test_perm_5_2(self):
        self.assertEqual(math.perm(5, 2), 20)

    def test_perm_10_3(self):
        self.assertEqual(math.perm(10, 3), 720)

class TestMathHypot(unittest.TestCase):
    def test_hypot_3_4(self):
        self.assertEqual(math.hypot(3, 4), 5.0)

    def test_hypot_5_12(self):
        self.assertEqual(math.hypot(5, 12), 13.0)

if __name__ == "__main__":
    unittest.main()
