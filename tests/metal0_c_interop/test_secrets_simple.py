"""Secrets module tests for metal0 C interop"""
import secrets
import unittest

class TestRandbelow(unittest.TestCase):
    def test_randbelow_10(self):
        result = secrets.randbelow(10)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 10)

    def test_randbelow_100(self):
        result = secrets.randbelow(100)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 100)

    def test_randbelow_1(self):
        result = secrets.randbelow(1)
        self.assertEqual(result, 0)

    def test_randbelow_1000(self):
        result = secrets.randbelow(1000)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 1000)

    def test_randbelow_5(self):
        result = secrets.randbelow(5)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 5)

class TestCompareDigest(unittest.TestCase):
    def test_compare_equal(self):
        result = secrets.compare_digest(b"hello", b"hello")
        self.assertTrue(result)

    def test_compare_not_equal(self):
        result = secrets.compare_digest(b"hello", b"world")
        self.assertFalse(result)

    def test_compare_different_length(self):
        result = secrets.compare_digest(b"hello", b"hi")
        self.assertFalse(result)

    def test_compare_empty(self):
        result = secrets.compare_digest(b"", b"")
        self.assertTrue(result)

    def test_compare_same_abc(self):
        result = secrets.compare_digest(b"abc", b"abc")
        self.assertTrue(result)

    def test_compare_different_abc(self):
        result = secrets.compare_digest(b"abc", b"xyz")
        self.assertFalse(result)

if __name__ == "__main__":
    unittest.main()
