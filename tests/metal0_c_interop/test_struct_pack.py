"""Struct pack C interop tests"""
import struct
import unittest

class TestPackByte(unittest.TestCase):
    def test_pack_byte_0(self):
        result = struct.pack('b', 0)
        self.assertEqual(result, b'\x00')

    def test_pack_byte_1(self):
        result = struct.pack('b', 1)
        self.assertEqual(result, b'\x01')

    def test_pack_byte_127(self):
        result = struct.pack('b', 127)
        self.assertEqual(result, b'\x7f')

    def test_pack_byte_neg1(self):
        result = struct.pack('b', -1)
        self.assertEqual(result, b'\xff')

    def test_pack_byte_neg128(self):
        result = struct.pack('b', -128)
        self.assertEqual(result, b'\x80')

class TestPackUnsignedByte(unittest.TestCase):
    def test_pack_ubyte_0(self):
        result = struct.pack('B', 0)
        self.assertEqual(result, b'\x00')

    def test_pack_ubyte_1(self):
        result = struct.pack('B', 1)
        self.assertEqual(result, b'\x01')

    def test_pack_ubyte_127(self):
        result = struct.pack('B', 127)
        self.assertEqual(result, b'\x7f')

    def test_pack_ubyte_255(self):
        result = struct.pack('B', 255)
        self.assertEqual(result, b'\xff')

class TestPackShort(unittest.TestCase):
    def test_pack_short_0(self):
        result = struct.pack('h', 0)
        self.assertIsInstance(result, bytes)

    def test_pack_short_1(self):
        result = struct.pack('h', 1)
        self.assertIsInstance(result, bytes)

    def test_pack_short_neg1(self):
        result = struct.pack('h', -1)
        self.assertIsInstance(result, bytes)

class TestPackInt(unittest.TestCase):
    def test_pack_int_0(self):
        result = struct.pack('i', 0)
        self.assertIsInstance(result, bytes)

    def test_pack_int_1(self):
        result = struct.pack('i', 1)
        self.assertIsInstance(result, bytes)

    def test_pack_int_neg1(self):
        result = struct.pack('i', -1)
        self.assertIsInstance(result, bytes)

    def test_pack_int_1000(self):
        result = struct.pack('i', 1000)
        self.assertIsInstance(result, bytes)

class TestPackLong(unittest.TestCase):
    def test_pack_long_0(self):
        result = struct.pack('l', 0)
        self.assertIsInstance(result, bytes)

    def test_pack_long_1(self):
        result = struct.pack('l', 1)
        self.assertIsInstance(result, bytes)

    def test_pack_long_neg1(self):
        result = struct.pack('l', -1)
        self.assertIsInstance(result, bytes)

class TestPackLongLong(unittest.TestCase):
    def test_pack_longlong_0(self):
        result = struct.pack('q', 0)
        self.assertIsInstance(result, bytes)

    def test_pack_longlong_1(self):
        result = struct.pack('q', 1)
        self.assertIsInstance(result, bytes)

    def test_pack_longlong_neg1(self):
        result = struct.pack('q', -1)
        self.assertIsInstance(result, bytes)

if __name__ == "__main__":
    unittest.main()
