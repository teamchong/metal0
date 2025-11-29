"""Comprehensive string module tests for metal0"""
import string
import unittest

class TestStringConstants(unittest.TestCase):
    def test_ascii_lowercase(self):
        self.assertEqual(string.ascii_lowercase, "abcdefghijklmnopqrstuvwxyz")

    def test_ascii_lowercase_length(self):
        self.assertEqual(len(string.ascii_lowercase), 26)

    def test_ascii_lowercase_starts_with_a(self):
        self.assertTrue(string.ascii_lowercase.startswith("a"))

    def test_ascii_lowercase_ends_with_z(self):
        self.assertTrue(string.ascii_lowercase.endswith("z"))

    def test_ascii_uppercase(self):
        self.assertEqual(string.ascii_uppercase, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    def test_ascii_uppercase_length(self):
        self.assertEqual(len(string.ascii_uppercase), 26)

    def test_ascii_uppercase_starts_with_A(self):
        self.assertTrue(string.ascii_uppercase.startswith("A"))

    def test_ascii_uppercase_ends_with_Z(self):
        self.assertTrue(string.ascii_uppercase.endswith("Z"))

    def test_ascii_letters(self):
        self.assertIn("a", string.ascii_letters)
        self.assertIn("Z", string.ascii_letters)
        self.assertEqual(len(string.ascii_letters), 52)

    def test_ascii_letters_lowercase(self):
        self.assertIn("m", string.ascii_letters)

    def test_ascii_letters_uppercase(self):
        self.assertIn("M", string.ascii_letters)

    def test_digits(self):
        self.assertEqual(string.digits, "0123456789")

    def test_digits_length(self):
        self.assertEqual(len(string.digits), 10)

    def test_digits_starts_with_0(self):
        self.assertTrue(string.digits.startswith("0"))

    def test_digits_ends_with_9(self):
        self.assertTrue(string.digits.endswith("9"))

    def test_hexdigits(self):
        self.assertEqual(string.hexdigits, "0123456789abcdefABCDEF")

    def test_hexdigits_length(self):
        self.assertEqual(len(string.hexdigits), 22)

    def test_hexdigits_contains_a(self):
        self.assertIn("a", string.hexdigits)

    def test_hexdigits_contains_F(self):
        self.assertIn("F", string.hexdigits)

    def test_octdigits(self):
        self.assertEqual(string.octdigits, "01234567")

    def test_octdigits_length(self):
        self.assertEqual(len(string.octdigits), 8)

    def test_punctuation(self):
        self.assertIn("!", string.punctuation)
        self.assertIn(".", string.punctuation)
        self.assertIn("@", string.punctuation)
        self.assertTrue(len(string.punctuation) > 20)

    def test_punctuation_comma(self):
        self.assertIn(",", string.punctuation)

    def test_punctuation_semicolon(self):
        self.assertIn(";", string.punctuation)

    def test_punctuation_colon(self):
        self.assertIn(":", string.punctuation)

    def test_whitespace(self):
        self.assertIn(" ", string.whitespace)
        self.assertTrue(len(string.whitespace) >= 6)

    def test_printable_contains_letters(self):
        self.assertIn("a", string.printable)
        self.assertIn("Z", string.printable)

    def test_printable_contains_digits(self):
        self.assertIn("0", string.printable)
        self.assertIn("9", string.printable)

    def test_printable_contains_punctuation(self):
        self.assertIn("!", string.printable)

    def test_printable_contains_space(self):
        self.assertIn(" ", string.printable)

    def test_printable_length(self):
        self.assertTrue(len(string.printable) > 90)

if __name__ == "__main__":
    unittest.main()
