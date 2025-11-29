"""Simple bisect module tests for metal0"""
import bisect
import unittest

class TestBisectLeft(unittest.TestCase):
    def test_bisect_left_single(self):
        result = bisect.bisect_left([5], 5)
        self.assertEqual(result, 0)

    def test_bisect_left_start(self):
        result = bisect.bisect_left([1, 2, 3, 4, 5], 0)
        self.assertEqual(result, 0)

    def test_bisect_left_end(self):
        result = bisect.bisect_left([1, 2, 3, 4, 5], 6)
        self.assertEqual(result, 5)

    def test_bisect_left_middle(self):
        result = bisect.bisect_left([1, 2, 4, 5], 3)
        self.assertEqual(result, 2)

    def test_bisect_left_exact(self):
        result = bisect.bisect_left([1, 2, 3, 4, 5], 3)
        self.assertEqual(result, 2)

    def test_bisect_left_duplicates(self):
        result = bisect.bisect_left([1, 2, 2, 2, 3], 2)
        self.assertEqual(result, 1)

class TestBisectRight(unittest.TestCase):
    def test_bisect_right_single(self):
        result = bisect.bisect_right([5], 5)
        self.assertEqual(result, 1)

    def test_bisect_right_start(self):
        result = bisect.bisect_right([1, 2, 3, 4, 5], 0)
        self.assertEqual(result, 0)

    def test_bisect_right_end(self):
        result = bisect.bisect_right([1, 2, 3, 4, 5], 6)
        self.assertEqual(result, 5)

    def test_bisect_right_middle(self):
        result = bisect.bisect_right([1, 2, 4, 5], 3)
        self.assertEqual(result, 2)

    def test_bisect_right_exact(self):
        result = bisect.bisect_right([1, 2, 3, 4, 5], 3)
        self.assertEqual(result, 3)

    def test_bisect_right_duplicates(self):
        result = bisect.bisect_right([1, 2, 2, 2, 3], 2)
        self.assertEqual(result, 4)

class TestBisect(unittest.TestCase):
    def test_bisect_alias(self):
        result = bisect.bisect([1, 2, 3, 4, 5], 3)
        self.assertEqual(result, 3)

    def test_bisect_basic(self):
        result = bisect.bisect([10, 20, 30], 25)
        self.assertEqual(result, 2)

if __name__ == "__main__":
    unittest.main()
