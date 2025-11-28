"""Test Python unittest framework support."""
import unittest


class TestBasicAssertions(unittest.TestCase):
    """Test basic assertion methods."""

    def test_assertEqual(self):
        self.assertEqual(1 + 1, 2)
        self.assertEqual("hello", "hello")

    def test_assertNotEqual(self):
        self.assertNotEqual(1, 2)
        self.assertNotEqual("a", "b")

    def test_assertTrue(self):
        self.assertTrue(True)
        self.assertTrue(1 > 0)

    def test_assertFalse(self):
        self.assertFalse(False)
        self.assertFalse(1 < 0)


class TestComparisonAssertions(unittest.TestCase):
    """Test comparison assertion methods."""

    def test_assertGreater(self):
        self.assertGreater(5, 3)

    def test_assertLess(self):
        self.assertLess(3, 5)

    def test_assertGreaterEqual(self):
        self.assertGreaterEqual(5, 5)
        self.assertGreaterEqual(6, 5)

    def test_assertLessEqual(self):
        self.assertLessEqual(5, 5)
        self.assertLessEqual(4, 5)


if __name__ == "__main__":
    unittest.main()
