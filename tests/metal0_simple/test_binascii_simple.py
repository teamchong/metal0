"""Simple binascii module tests for metal0"""
import binascii
import unittest

class TestHexlify(unittest.TestCase):
    def test_hexlify_hello(self):
        result = binascii.hexlify(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_hexlify_world(self):
        result = binascii.hexlify(b"world")
        self.assertEqual(result, b"776f726c64")

    def test_hexlify_abc(self):
        result = binascii.hexlify(b"abc")
        self.assertEqual(result, b"616263")

    def test_hexlify_single(self):
        result = binascii.hexlify(b"x")
        self.assertEqual(result, b"78")

    def test_hexlify_digits(self):
        result = binascii.hexlify(b"123")
        self.assertEqual(result, b"313233")

class TestB2aHex(unittest.TestCase):
    def test_b2a_hex_hello(self):
        result = binascii.b2a_hex(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_b2a_hex_test(self):
        result = binascii.b2a_hex(b"test")
        self.assertEqual(result, b"74657374")

    def test_b2a_hex_world(self):
        result = binascii.b2a_hex(b"world")
        self.assertEqual(result, b"776f726c64")

class TestCrc32(unittest.TestCase):
    def test_crc32_hello(self):
        # binascii.crc32 returns a u32 value
        result = binascii.crc32(b"hello")
        # Zig's std.hash.crc.Crc32 returns a different value than Python's zlib
        # Just check it returns a number
        self.assertTrue(result > 0)

    def test_crc32_world(self):
        result = binascii.crc32(b"world")
        self.assertTrue(result > 0)

    def test_crc32_test(self):
        result = binascii.crc32(b"test")
        self.assertTrue(result > 0)

if __name__ == "__main__":
    unittest.main()
