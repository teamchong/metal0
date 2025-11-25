import unittest

class TestSkip(unittest.TestCase):
    def test_normal(self):
        self.assertTrue(True)

    def test_skip_me(self):
        """skip: WIP - not implemented yet"""
        # This test should be skipped
        # If it runs, the assertion will fail
        self.assertEqual(1, 999)

    def test_also_normal(self):
        self.assertEqual(1, 1)

    def test_skip_uppercase(self):
        """SKIP: Also works with uppercase"""
        self.assertEqual(2, 999)

unittest.main()
