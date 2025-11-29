"""Simple math module tests for metal0"""
import math
import unittest

class TestMathBasic(unittest.TestCase):
    def test_sqrt(self):
        self.assertEqual(math.sqrt(4), 2.0)
        self.assertEqual(math.sqrt(9), 3.0)
        self.assertEqual(math.sqrt(16), 4.0)
    
    def test_floor_ceil(self):
        self.assertEqual(math.floor(3.7), 3)
        self.assertEqual(math.ceil(3.2), 4)
        self.assertEqual(math.floor(-3.7), -4)
        self.assertEqual(math.ceil(-3.2), -3)
    
    def test_pow(self):
        self.assertEqual(math.pow(2, 3), 8.0)
        self.assertEqual(math.pow(3, 2), 9.0)
    
    def test_abs(self):
        self.assertEqual(math.fabs(-5.5), 5.5)
        self.assertEqual(math.fabs(5.5), 5.5)
    
    def test_trig(self):
        self.assertAlmostEqual(math.sin(0), 0.0, places=5)
        self.assertAlmostEqual(math.cos(0), 1.0, places=5)
        self.assertAlmostEqual(math.tan(0), 0.0, places=5)
    
    def test_log(self):
        self.assertAlmostEqual(math.log(math.e), 1.0, places=5)
        self.assertEqual(math.log10(100), 2.0)
        self.assertEqual(math.log2(8), 3.0)
    
    def test_constants(self):
        self.assertTrue(abs(math.pi - 3.14159265) < 0.0001)
        self.assertTrue(abs(math.e - 2.71828182) < 0.0001)

if __name__ == "__main__":
    unittest.main()
