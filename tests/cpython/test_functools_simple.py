"""Simple functools module tests for metal0"""
import functools
import unittest

class TestFunctoolsReduce(unittest.TestCase):
    def test_reduce_add(self):
        # Test reduce with addition
        result = functools.reduce(lambda x, y: x + y, [1, 2, 3, 4])
        self.assertEqual(result, 10)

    def test_reduce_multiply(self):
        # Test reduce with multiplication
        result = functools.reduce(lambda x, y: x * y, [1, 2, 3, 4])
        self.assertEqual(result, 24)

    def test_reduce_with_initial(self):
        # Test reduce with initial value
        result = functools.reduce(lambda x, y: x + y, [1, 2, 3], 10)
        self.assertEqual(result, 16)

if __name__ == "__main__":
    unittest.main()
