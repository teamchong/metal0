"""Binascii edge case tests for metal0 C interop"""
import binascii
import unittest

class TestHexlifyAscii(unittest.TestCase):
    def test_hexlify_hello(self):
        result = binascii.hexlify(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_hexlify_world(self):
        result = binascii.hexlify(b"world")
        self.assertEqual(result, b"776f726c64")

    def test_hexlify_abc(self):
        result = binascii.hexlify(b"abc")
        self.assertEqual(result, b"616263")

    def test_hexlify_ABC(self):
        result = binascii.hexlify(b"ABC")
        self.assertEqual(result, b"414243")

    def test_hexlify_digits(self):
        result = binascii.hexlify(b"123")
        self.assertEqual(result, b"313233")

    def test_hexlify_empty(self):
        result = binascii.hexlify(b"")
        self.assertEqual(result, b"")

    def test_hexlify_space(self):
        result = binascii.hexlify(b" ")
        self.assertEqual(result, b"20")

class TestUnhexlifyAscii(unittest.TestCase):
    def test_unhexlify_hello(self):
        result = binascii.unhexlify(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_unhexlify_world(self):
        result = binascii.unhexlify(b"776f726c64")
        self.assertEqual(result, b"world")

    def test_unhexlify_abc(self):
        result = binascii.unhexlify(b"616263")
        self.assertEqual(result, b"abc")

    def test_unhexlify_empty(self):
        result = binascii.unhexlify(b"")
        self.assertEqual(result, b"")

    def test_unhexlify_uppercase(self):
        result = binascii.unhexlify(b"414243")
        self.assertEqual(result, b"ABC")

class TestCrc32Values(unittest.TestCase):
    def test_crc32_hello(self):
        result = binascii.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = binascii.crc32(b"world")
        self.assertTrue(result > 0)

    def test_crc32_empty(self):
        result = binascii.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_abc(self):
        result = binascii.crc32(b"abc")
        self.assertTrue(result > 0)

class TestB2aHex(unittest.TestCase):
    def test_b2a_hex_hello(self):
        result = binascii.b2a_hex(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_b2a_hex_test(self):
        result = binascii.b2a_hex(b"test")
        self.assertEqual(result, b"74657374")

    def test_b2a_hex_empty(self):
        result = binascii.b2a_hex(b"")
        self.assertEqual(result, b"")

class TestA2bHex(unittest.TestCase):
    def test_a2b_hex_hello(self):
        result = binascii.a2b_hex(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_a2b_hex_test(self):
        result = binascii.a2b_hex(b"74657374")
        self.assertEqual(result, b"test")

    def test_a2b_hex_empty(self):
        result = binascii.a2b_hex(b"")
        self.assertEqual(result, b"")

if __name__ == "__main__":
    unittest.main()
