"""Comprehensive math module tests for metal0"""
import math
import unittest

class TestMathBasic(unittest.TestCase):
    def test_abs_positive(self):
        self.assertEqual(math.fabs(5), 5.0)

    def test_abs_negative(self):
        self.assertEqual(math.fabs(-5), 5.0)

    def test_ceil_positive(self):
        self.assertEqual(math.ceil(4.2), 5)

    def test_ceil_negative(self):
        self.assertEqual(math.ceil(-4.2), -4)

    def test_floor_positive(self):
        self.assertEqual(math.floor(4.8), 4)

    def test_floor_negative(self):
        self.assertEqual(math.floor(-4.8), -5)

    def test_trunc_positive(self):
        self.assertEqual(math.trunc(4.9), 4)

    def test_trunc_negative(self):
        self.assertEqual(math.trunc(-4.9), -4)

class TestMathPower(unittest.TestCase):
    def test_sqrt_4(self):
        self.assertEqual(math.sqrt(4), 2.0)

    def test_sqrt_9(self):
        self.assertEqual(math.sqrt(9), 3.0)

    def test_sqrt_16(self):
        self.assertEqual(math.sqrt(16), 4.0)

    def test_pow_2_3(self):
        self.assertEqual(math.pow(2, 3), 8.0)

    def test_pow_3_2(self):
        self.assertEqual(math.pow(3, 2), 9.0)

    def test_pow_10_0(self):
        self.assertEqual(math.pow(10, 0), 1.0)

class TestMathLog(unittest.TestCase):
    def test_log_e(self):
        self.assertAlmostEqual(math.log(math.e), 1.0, places=5)

    def test_log10_10(self):
        self.assertEqual(math.log10(10), 1.0)

    def test_log10_100(self):
        self.assertEqual(math.log10(100), 2.0)

    def test_log2_2(self):
        self.assertEqual(math.log2(2), 1.0)

    def test_log2_8(self):
        self.assertEqual(math.log2(8), 3.0)

    def test_exp_0(self):
        self.assertEqual(math.exp(0), 1.0)

    def test_exp_1(self):
        self.assertAlmostEqual(math.exp(1), math.e, places=5)

class TestMathTrig(unittest.TestCase):
    def test_sin_0(self):
        self.assertEqual(math.sin(0), 0.0)

    def test_cos_0(self):
        self.assertEqual(math.cos(0), 1.0)

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

class TestMathConstants(unittest.TestCase):
    def test_pi(self):
        self.assertAlmostEqual(math.pi, 3.141592653589793, places=10)

    def test_e(self):
        self.assertAlmostEqual(math.e, 2.718281828459045, places=10)

    def test_tau(self):
        self.assertAlmostEqual(math.tau, 6.283185307179586, places=10)

    def test_inf_positive(self):
        self.assertTrue(math.inf > 0)

    def test_inf_comparison(self):
        self.assertTrue(math.inf > 1e308)

class TestMathMisc(unittest.TestCase):
    def test_copysign_positive(self):
        self.assertEqual(math.copysign(1.0, -1.0), -1.0)

    def test_copysign_negative(self):
        self.assertEqual(math.copysign(-1.0, 1.0), 1.0)

    def test_fmod_positive(self):
        self.assertAlmostEqual(math.fmod(10.0, 3.0), 1.0, places=5)

    def test_modf_positive(self):
        frac, integer = math.modf(3.5)
        self.assertAlmostEqual(frac, 0.5, places=5)
        self.assertAlmostEqual(integer, 3.0, places=5)

    def test_ldexp(self):
        self.assertEqual(math.ldexp(1.0, 3), 8.0)

    def test_frexp(self):
        m, e = math.frexp(8.0)
        # m should be 0.5, e should be 4 (0.5 * 2^4 = 8.0)
        self.assertAlmostEqual(m, 0.5, places=5)
        self.assertEqual(e, 4)

    def test_hypot(self):
        self.assertEqual(math.hypot(3, 4), 5.0)

    def test_hypot_origin(self):
        self.assertEqual(math.hypot(0, 0), 0.0)

if __name__ == "__main__":
    unittest.main()
