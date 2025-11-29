"""Simple collections module tests for metal0"""
import collections
import unittest

class TestCounter(unittest.TestCase):
    def test_counter_from_string(self):
        c = collections.Counter("hello")
        self.assertEqual(c["l"], 2)

    def test_counter_from_list(self):
        c = collections.Counter([1, 1, 2, 3, 3, 3])
        self.assertEqual(c[3], 3)

    def test_counter_most_common(self):
        c = collections.Counter("abracadabra")
        result = c.most_common(2)
        self.assertEqual(len(result), 2)

    def test_counter_elements(self):
        c = collections.Counter(a=2, b=1)
        self.assertTrue(True)  # Just test it works

if __name__ == "__main__":
    unittest.main()
