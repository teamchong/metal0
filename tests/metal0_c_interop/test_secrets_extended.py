"""Extended secrets module tests for metal0 C interop"""
import secrets
import unittest

class TestTokenHexIsString(unittest.TestCase):
    def test_token_hex_16_is_string(self):
        result = secrets.token_hex(16)
        self.assertIsInstance(result, str)

    def test_token_hex_8_is_string(self):
        result = secrets.token_hex(8)
        self.assertIsInstance(result, str)

    def test_token_hex_4_is_string(self):
        result = secrets.token_hex(4)
        self.assertIsInstance(result, str)

    def test_token_hex_32_is_string(self):
        result = secrets.token_hex(32)
        self.assertIsInstance(result, str)

    def test_token_hex_1_is_string(self):
        result = secrets.token_hex(1)
        self.assertIsInstance(result, str)

class TestRandbelowExtended(unittest.TestCase):
    def test_randbelow_2(self):
        result = secrets.randbelow(2)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 2)

    def test_randbelow_50(self):
        result = secrets.randbelow(50)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 50)

    def test_randbelow_256(self):
        result = secrets.randbelow(256)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 256)

    def test_randbelow_10000(self):
        result = secrets.randbelow(10000)
        self.assertGreaterEqual(result, 0)
        self.assertLess(result, 10000)

class TestCompareDigestExtended(unittest.TestCase):
    def test_compare_single_char(self):
        result = secrets.compare_digest(b"a", b"a")
        self.assertTrue(result)

    def test_compare_single_char_different(self):
        result = secrets.compare_digest(b"a", b"b")
        self.assertFalse(result)

    def test_compare_numbers(self):
        result = secrets.compare_digest(b"12345", b"12345")
        self.assertTrue(result)

    def test_compare_numbers_different(self):
        result = secrets.compare_digest(b"12345", b"12346")
        self.assertFalse(result)

    def test_compare_long_same(self):
        result = secrets.compare_digest(b"abcdefghij", b"abcdefghij")
        self.assertTrue(result)

    def test_compare_long_different(self):
        result = secrets.compare_digest(b"abcdefghij", b"abcdefghik")
        self.assertFalse(result)

if __name__ == "__main__":
    unittest.main()
