"""Minimal deque tests for metal0"""
import collections
import unittest

class TestDequeBasic(unittest.TestCase):
    def test_deque_append(self):
        d = collections.deque()
        d.append(1)
        self.assertEqual(len(d), 1)

    def test_deque_appendleft(self):
        d = collections.deque()
        d.appendleft(1)
        self.assertEqual(len(d), 1)

    def test_deque_pop(self):
        d = collections.deque([1, 2, 3])
        self.assertEqual(d.pop(), 3)

    def test_deque_popleft(self):
        d = collections.deque([1, 2, 3])
        self.assertEqual(d.popleft(), 1)

if __name__ == "__main__":
    unittest.main()
