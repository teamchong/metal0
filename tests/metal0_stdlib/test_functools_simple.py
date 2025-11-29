"""Comprehensive functools module tests for metal0"""
import functools
import unittest

class TestFunctoolsReduceAdd(unittest.TestCase):
    def test_reduce_add_basic(self):
        result = functools.reduce(lambda x, y: x + y, [1, 2, 3, 4])
        self.assertEqual(result, 10)

    def test_reduce_add_two_elements(self):
        result = functools.reduce(lambda x, y: x + y, [5, 10])
        self.assertEqual(result, 15)

    def test_reduce_add_single(self):
        result = functools.reduce(lambda x, y: x + y, [42])
        self.assertEqual(result, 42)

    def test_reduce_add_with_initial(self):
        result = functools.reduce(lambda x, y: x + y, [1, 2, 3], 10)
        self.assertEqual(result, 16)

    def test_reduce_add_with_initial_zero(self):
        result = functools.reduce(lambda x, y: x + y, [1, 2, 3], 0)
        self.assertEqual(result, 6)

class TestFunctoolsReduceMultiply(unittest.TestCase):
    def test_reduce_multiply_basic(self):
        result = functools.reduce(lambda x, y: x * y, [1, 2, 3, 4])
        self.assertEqual(result, 24)

    def test_reduce_multiply_two_elements(self):
        result = functools.reduce(lambda x, y: x * y, [3, 7])
        self.assertEqual(result, 21)

    def test_reduce_multiply_with_initial(self):
        result = functools.reduce(lambda x, y: x * y, [1, 2, 3], 10)
        self.assertEqual(result, 60)

    def test_reduce_multiply_with_one(self):
        result = functools.reduce(lambda x, y: x * y, [2, 3, 4], 1)
        self.assertEqual(result, 24)

class TestFunctoolsReduceOther(unittest.TestCase):
    def test_reduce_subtract(self):
        result = functools.reduce(lambda x, y: x - y, [10, 3, 2])
        self.assertEqual(result, 5)

    def test_reduce_subtract_two(self):
        result = functools.reduce(lambda x, y: x - y, [100, 25])
        self.assertEqual(result, 75)

    def test_reduce_add_large(self):
        result = functools.reduce(lambda x, y: x + y, [100, 200, 300, 400])
        self.assertEqual(result, 1000)

if __name__ == "__main__":
    unittest.main()
