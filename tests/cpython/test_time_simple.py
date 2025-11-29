"""Simple time module tests for metal0"""
import time
import unittest

class TestTimeBasic(unittest.TestCase):
    def test_time(self):
        # time.time() should return positive number
        t = time.time()
        self.assertTrue(t > 0)

    def test_time_increases(self):
        t1 = time.time()
        t2 = time.time()
        self.assertTrue(t2 >= t1)

    def test_monotonic(self):
        t1 = time.monotonic()
        t2 = time.monotonic()
        self.assertTrue(t2 >= t1)

if __name__ == "__main__":
    unittest.main()
