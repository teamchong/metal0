"""Binascii roundtrip tests for metal0 C interop"""
import binascii
import unittest

class TestHexlifyUnhexlifyRoundtrip(unittest.TestCase):
    def test_roundtrip_a(self):
        original = b"a"
        hexified = binascii.hexlify(original)
        unhexified = binascii.unhexlify(hexified)
        self.assertEqual(unhexified, original)

    def test_roundtrip_ab(self):
        original = b"ab"
        hexified = binascii.hexlify(original)
        unhexified = binascii.unhexlify(hexified)
        self.assertEqual(unhexified, original)

    def test_roundtrip_abc(self):
        original = b"abc"
        hexified = binascii.hexlify(original)
        unhexified = binascii.unhexlify(hexified)
        self.assertEqual(unhexified, original)

    def test_roundtrip_hello(self):
        original = b"hello"
        hexified = binascii.hexlify(original)
        unhexified = binascii.unhexlify(hexified)
        self.assertEqual(unhexified, original)

    def test_roundtrip_world(self):
        original = b"world"
        hexified = binascii.hexlify(original)
        unhexified = binascii.unhexlify(hexified)
        self.assertEqual(unhexified, original)

class TestHexlifyValues(unittest.TestCase):
    def test_hexlify_a(self):
        result = binascii.hexlify(b"a")
        self.assertEqual(result, b"61")

    def test_hexlify_ab(self):
        result = binascii.hexlify(b"ab")
        self.assertEqual(result, b"6162")

    def test_hexlify_abc(self):
        result = binascii.hexlify(b"abc")
        self.assertEqual(result, b"616263")

    def test_hexlify_hello(self):
        result = binascii.hexlify(b"hello")
        self.assertEqual(result, b"68656c6c6f")

    def test_hexlify_123(self):
        result = binascii.hexlify(b"123")
        self.assertEqual(result, b"313233")

class TestUnhexlifyValues(unittest.TestCase):
    def test_unhexlify_61(self):
        result = binascii.unhexlify(b"61")
        self.assertEqual(result, b"a")

    def test_unhexlify_6162(self):
        result = binascii.unhexlify(b"6162")
        self.assertEqual(result, b"ab")

    def test_unhexlify_616263(self):
        result = binascii.unhexlify(b"616263")
        self.assertEqual(result, b"abc")

    def test_unhexlify_68656c6c6f(self):
        result = binascii.unhexlify(b"68656c6c6f")
        self.assertEqual(result, b"hello")

    def test_unhexlify_313233(self):
        result = binascii.unhexlify(b"313233")
        self.assertEqual(result, b"123")

class TestBinasciiCrc32(unittest.TestCase):
    def test_crc32_a(self):
        result = binascii.crc32(b"a")
        self.assertEqual(result, 3904355907)

    def test_crc32_hello(self):
        result = binascii.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_abc(self):
        result = binascii.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_test(self):
        result = binascii.crc32(b"test")
        self.assertEqual(result, 3632233996)

if __name__ == "__main__":
    unittest.main()
