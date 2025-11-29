"""Simple sys module tests for metal0"""
import sys
import unittest

class TestSysBasic(unittest.TestCase):
    def test_platform_darwin(self):
        # Platform should contain darwin on macOS
        self.assertIn("darwin", sys.platform)

    def test_maxsize(self):
        # maxsize should be a large positive integer
        self.assertTrue(sys.maxsize > 0)
        self.assertTrue(sys.maxsize > 1000000)

    def test_byteorder(self):
        # byteorder should be 'little' on most systems
        self.assertEqual(sys.byteorder, "little")

if __name__ == "__main__":
    unittest.main()
