"""Simple collections module tests for metal0"""
import collections
import unittest

class TestCollectionsBasic(unittest.TestCase):
    """Test basic collections functionality"""

    def test_counter_from_list(self):
        # Counter with initial iterable
        c = collections.Counter([1, 1, 2, 3, 3, 3])
        self.assertEqual(c[1], 2)
        self.assertEqual(c[3], 3)

    def test_counter_from_string(self):
        c = collections.Counter("aab")
        self.assertEqual(c["a"], 2)
        self.assertEqual(c["b"], 1)

if __name__ == "__main__":
    unittest.main()
