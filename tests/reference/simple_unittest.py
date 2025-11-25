"""Simple unittest test for PyAOT"""
import unittest

class TestMath(unittest.TestCase):
    def test_add(self):
        self.assertEqual(2 + 2, 4)

    def test_sub(self):
        self.assertTrue(5 - 3 == 2)

if __name__ == "__main__":
    unittest.main()
