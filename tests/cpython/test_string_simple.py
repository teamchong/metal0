"""Simple string module tests for metal0"""
import string
import unittest

class TestStringConstants(unittest.TestCase):
    def test_ascii_lowercase(self):
        self.assertEqual(string.ascii_lowercase, "abcdefghijklmnopqrstuvwxyz")

    def test_ascii_uppercase(self):
        self.assertEqual(string.ascii_uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    def test_ascii_letters(self):
        # Check it contains both lowercase and uppercase
        self.assertIn("a", string.ascii_letters)
        self.assertIn("Z", string.ascii_letters)
        self.assertEqual(len(string.ascii_letters), 52)

    def test_digits(self):
        self.assertEqual(string.digits, "0123456789")

    def test_hexdigits(self):
        self.assertEqual(string.hexdigits, "0123456789abcdefABCDEF")

    def test_octdigits(self):
        self.assertEqual(string.octdigits, "01234567")

    def test_punctuation(self):
        # Check some common punctuation characters
        self.assertIn("!", string.punctuation)
        self.assertIn(".", string.punctuation)
        self.assertIn("@", string.punctuation)
        self.assertTrue(len(string.punctuation) > 20)

    def test_whitespace(self):
        # whitespace contains space and has reasonable length
        self.assertIn(" ", string.whitespace)
        self.assertTrue(len(string.whitespace) >= 6)

if __name__ == "__main__":
    unittest.main()
