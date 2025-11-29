"""Basic itertools module tests for metal0"""
import itertools
import unittest

class TestItertoolsRepeat(unittest.TestCase):
    def test_repeat_with_times(self):
        result = list(itertools.repeat(5, 3))
        self.assertEqual(len(result), 3)

    def test_repeat_zero_times(self):
        result = list(itertools.repeat(5, 0))
        self.assertEqual(len(result), 0)

    def test_repeat_one_time(self):
        result = list(itertools.repeat(42, 1))
        self.assertEqual(len(result), 1)

class TestItertoolsChain(unittest.TestCase):
    def test_chain_two_lists(self):
        a = [1, 2]
        b = [3, 4]
        result = list(itertools.chain(a, b))
        self.assertEqual(len(result), 4)

    def test_chain_three_lists(self):
        a = [1]
        b = [2]
        c = [3]
        result = list(itertools.chain(a, b, c))
        self.assertEqual(len(result), 3)

if __name__ == "__main__":
    unittest.main()
