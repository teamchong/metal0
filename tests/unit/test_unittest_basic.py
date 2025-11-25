import unittest

class TestAssertions(unittest.TestCase):
    def test_equal(self):
        self.assertEqual(1, 1)
        self.assertEqual("hello", "hello")

    def test_true(self):
        self.assertTrue(True)
        self.assertTrue(1 == 1)

    def test_false(self):
        self.assertFalse(False)
        self.assertFalse(1 == 2)

unittest.main()
