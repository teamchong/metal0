"""Comprehensive binascii module tests for metal0 C interop"""
import binascii
import unittest

class TestHexlifyBasic(unittest.TestCase):
    def test_hexlify_hello(self):
        result = binascii.hexlify(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_hexlify_world(self):
        result = binascii.hexlify(b"world")
        self.assertEqual(result, b"776f726c64")

    def test_hexlify_empty(self):
        result = binascii.hexlify(b"")
        self.assertEqual(result, b"")

    def test_hexlify_abc(self):
        result = binascii.hexlify(b"abc")
        self.assertEqual(result, b"616263")

    def test_hexlify_digits(self):
        result = binascii.hexlify(b"123")
        self.assertEqual(result, b"313233")

class TestHexlifyMore(unittest.TestCase):
    def test_hexlify_space(self):
        result = binascii.hexlify(b" ")
        self.assertEqual(result, b"20")

    def test_hexlify_at(self):
        result = binascii.hexlify(b"@")
        self.assertEqual(result, b"40")

    def test_hexlify_mixed(self):
        result = binascii.hexlify(b"AB")
        self.assertEqual(result, b"4142")

    def test_hexlify_punct(self):
        result = binascii.hexlify(b"!?")
        self.assertEqual(result, b"213f")

class TestUnhexlifyBasic(unittest.TestCase):
    def test_unhexlify_hello(self):
        result = binascii.unhexlify(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_unhexlify_world(self):
        result = binascii.unhexlify(b"776f726c64")
        self.assertEqual(result, b"world")

    def test_unhexlify_empty(self):
        result = binascii.unhexlify(b"")
        self.assertEqual(result, b"")

    def test_unhexlify_abc(self):
        result = binascii.unhexlify(b"616263")
        self.assertEqual(result, b"abc")

class TestUnhexlifyMore(unittest.TestCase):
    def test_unhexlify_space(self):
        result = binascii.unhexlify(b"20")
        self.assertEqual(result, b" ")

    def test_unhexlify_at(self):
        result = binascii.unhexlify(b"40")
        self.assertEqual(result, b"@")

    def test_unhexlify_test(self):
        result = binascii.unhexlify(b"74657374")
        self.assertEqual(result, b"test")

class TestB2aHex(unittest.TestCase):
    def test_b2a_hex_hello(self):
        result = binascii.b2a_hex(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_b2a_hex_world(self):
        result = binascii.b2a_hex(b"world")
        self.assertEqual(result, b"776f726c64")

    def test_b2a_hex_empty(self):
        result = binascii.b2a_hex(b"")
        self.assertEqual(result, b"")

    def test_b2a_hex_test(self):
        result = binascii.b2a_hex(b"test")
        self.assertEqual(result, b"74657374")

class TestA2bHex(unittest.TestCase):
    def test_a2b_hex_hello(self):
        result = binascii.a2b_hex(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_a2b_hex_world(self):
        result = binascii.a2b_hex(b"776f726c64")
        self.assertEqual(result, b"world")

    def test_a2b_hex_empty(self):
        result = binascii.a2b_hex(b"")
        self.assertEqual(result, b"")

class TestCrc32(unittest.TestCase):
    def test_crc32_hello(self):
        result = binascii.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = binascii.crc32(b"world")
        self.assertEqual(result, 980881731)

    def test_crc32_empty(self):
        result = binascii.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_abc(self):
        result = binascii.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_test(self):
        result = binascii.crc32(b"test")
        self.assertEqual(result, 3632233996)

class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_hello(self):
        # hexlify(b"hello") = b"68656c6c6f"
        result = binascii.unhexlify(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_roundtrip_world(self):
        # hexlify(b"world") = b"776f726c64"
        result = binascii.unhexlify(b"776f726c64")
        self.assertEqual(result, b"world")

    def test_roundtrip_abc(self):
        # hexlify(b"abc") = b"616263"
        result = binascii.unhexlify(b"616263")
        self.assertEqual(result, b"abc")

    def test_roundtrip_check(self):
        # Verify hexlify produces expected output
        result = binascii.hexlify(b"test")
        self.assertEqual(result, b"74657374")

class TestConsistency(unittest.TestCase):
    def test_hexlify_consistent(self):
        a = binascii.hexlify(b"test")
        b = binascii.hexlify(b"test")
        self.assertEqual(a, b)

    def test_crc32_consistent(self):
        a = binascii.crc32(b"test")
        b = binascii.crc32(b"test")
        self.assertEqual(a, b)

    def test_hexlify_b2a_same(self):
        result1 = binascii.hexlify(b"hello world")
        result2 = binascii.b2a_hex(b"hello world")
        self.assertEqual(result1, result2)

    def test_unhexlify_a2b_same(self):
        result1 = binascii.unhexlify(b"68656c6c6f")
        result2 = binascii.a2b_hex(b"68656c6c6f")
        self.assertEqual(result1, result2)

if __name__ == "__main__":
    unittest.main()
