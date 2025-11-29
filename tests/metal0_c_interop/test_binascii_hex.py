"""Binascii hex encoding tests for metal0 C interop"""
import binascii
import unittest

class TestHexlifyLong(unittest.TestCase):
    def test_hexlify_sentence(self):
        result = binascii.hexlify(b"The quick brown")
        self.assertEqual(result, b"54686520717569636b2062726f776e")

    def test_hexlify_numbers(self):
        result = binascii.hexlify(b"1234567890")
        self.assertEqual(result, b"31323334353637383930")

    def test_hexlify_mixed(self):
        result = binascii.hexlify(b"abc123")
        self.assertEqual(result, b"616263313233")

    def test_hexlify_spaces(self):
        result = binascii.hexlify(b"   ")
        self.assertEqual(result, b"202020")

class TestUnhexlifyLong(unittest.TestCase):
    def test_unhexlify_sentence(self):
        result = binascii.unhexlify(b"54686520717569636b2062726f776e")
        self.assertEqual(result, b"The quick brown")

    def test_unhexlify_numbers(self):
        result = binascii.unhexlify(b"31323334353637383930")
        self.assertEqual(result, b"1234567890")

    def test_unhexlify_mixed(self):
        result = binascii.unhexlify(b"616263313233")
        self.assertEqual(result, b"abc123")

    def test_unhexlify_spaces(self):
        result = binascii.unhexlify(b"202020")
        self.assertEqual(result, b"   ")

class TestB2aHexLong(unittest.TestCase):
    def test_b2a_hex_sentence(self):
        result = binascii.b2a_hex(b"Hello World")
        self.assertEqual(result, b"48656c6c6f20576f726c64")

    def test_b2a_hex_empty(self):
        result = binascii.b2a_hex(b"")
        self.assertEqual(result, b"")

class TestA2bHexLong(unittest.TestCase):
    def test_a2b_hex_sentence(self):
        result = binascii.a2b_hex(b"48656c6c6f20576f726c64")
        self.assertEqual(result, b"Hello World")

    def test_a2b_hex_empty(self):
        result = binascii.a2b_hex(b"")
        self.assertEqual(result, b"")

class TestCrc32More(unittest.TestCase):
    def test_crc32_long_string(self):
        result = binascii.crc32(b"The quick brown fox")
        self.assertIsInstance(result, int)

    def test_crc32_numbers(self):
        result = binascii.crc32(b"1234567890")
        self.assertIsInstance(result, int)

    def test_crc32_positive(self):
        result = binascii.crc32(b"test")
        self.assertGreaterEqual(result, 0)

if __name__ == "__main__":
    unittest.main()
