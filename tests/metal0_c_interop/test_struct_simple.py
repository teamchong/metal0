"""Comprehensive struct module tests for metal0"""
import struct
import unittest

class TestStructPack(unittest.TestCase):
    def test_pack_int(self):
        result = struct.pack("i", 42)
        self.assertIsInstance(result, bytes)

    def test_pack_short(self):
        result = struct.pack("h", 100)
        self.assertIsInstance(result, bytes)

    def test_pack_byte(self):
        result = struct.pack("b", 65)
        self.assertIsInstance(result, bytes)

    def test_pack_unsigned_int(self):
        result = struct.pack("I", 1000)
        self.assertIsInstance(result, bytes)

    def test_pack_float(self):
        result = struct.pack("f", 3.14)
        self.assertIsInstance(result, bytes)

    def test_pack_double(self):
        result = struct.pack("d", 3.14159)
        self.assertIsInstance(result, bytes)

class TestStructUnpack(unittest.TestCase):
    def test_unpack_int(self):
        packed = struct.pack("i", 42)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 42)

    def test_unpack_short(self):
        packed = struct.pack("h", 100)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 100)

    def test_unpack_unsigned(self):
        packed = struct.pack("I", 1000)
        result = struct.unpack("I", packed)
        self.assertEqual(result[0], 1000)

class TestStructCalcsize(unittest.TestCase):
    def test_calcsize_int(self):
        size = struct.calcsize("i")
        self.assertEqual(size, 4)

    def test_calcsize_short(self):
        size = struct.calcsize("h")
        self.assertEqual(size, 2)

    def test_calcsize_byte(self):
        size = struct.calcsize("b")
        self.assertEqual(size, 1)

    def test_calcsize_double(self):
        size = struct.calcsize("d")
        self.assertEqual(size, 8)

    def test_calcsize_float(self):
        size = struct.calcsize("f")
        self.assertEqual(size, 4)

class TestStructRoundtrip(unittest.TestCase):
    def test_roundtrip_int(self):
        original = 12345
        packed = struct.pack("i", original)
        unpacked = struct.unpack("i", packed)
        self.assertEqual(unpacked[0], original)

    def test_roundtrip_negative(self):
        original = -100
        packed = struct.pack("i", original)
        unpacked = struct.unpack("i", packed)
        self.assertEqual(unpacked[0], original)

if __name__ == "__main__":
    unittest.main()
