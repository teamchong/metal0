"""Struct module boundary value tests for metal0 C interop"""
import struct
import unittest

class TestIntBoundaries(unittest.TestCase):
    def test_int_max(self):
        result = struct.pack("i", 2147483647)
        unpacked = struct.unpack("i", result)
        self.assertEqual(unpacked[0], 2147483647)

    def test_int_min(self):
        result = struct.pack("i", -2147483648)
        unpacked = struct.unpack("i", result)
        self.assertEqual(unpacked[0], -2147483648)

    def test_int_zero(self):
        result = struct.pack("i", 0)
        unpacked = struct.unpack("i", result)
        self.assertEqual(unpacked[0], 0)

class TestShortBoundaries(unittest.TestCase):
    def test_short_max(self):
        result = struct.pack("h", 32767)
        unpacked = struct.unpack("h", result)
        self.assertEqual(unpacked[0], 32767)

    def test_short_min(self):
        result = struct.pack("h", -32768)
        unpacked = struct.unpack("h", result)
        self.assertEqual(unpacked[0], -32768)

    def test_short_zero(self):
        result = struct.pack("h", 0)
        unpacked = struct.unpack("h", result)
        self.assertEqual(unpacked[0], 0)

class TestByteBoundaries(unittest.TestCase):
    def test_byte_max(self):
        result = struct.pack("b", 127)
        unpacked = struct.unpack("b", result)
        self.assertEqual(unpacked[0], 127)

    def test_byte_min(self):
        result = struct.pack("b", -128)
        unpacked = struct.unpack("b", result)
        self.assertEqual(unpacked[0], -128)

    def test_byte_zero(self):
        result = struct.pack("b", 0)
        unpacked = struct.unpack("b", result)
        self.assertEqual(unpacked[0], 0)

class TestUnsignedBoundaries(unittest.TestCase):
    def test_uint_max(self):
        result = struct.pack("I", 4294967295)
        unpacked = struct.unpack("I", result)
        self.assertEqual(unpacked[0], 4294967295)

    def test_ushort_max(self):
        result = struct.pack("H", 65535)
        unpacked = struct.unpack("H", result)
        self.assertEqual(unpacked[0], 65535)

    def test_ubyte_max(self):
        result = struct.pack("B", 255)
        unpacked = struct.unpack("B", result)
        self.assertEqual(unpacked[0], 255)

class TestLongLongBoundaries(unittest.TestCase):
    def test_longlong_large(self):
        result = struct.pack("q", 1000000000000)
        unpacked = struct.unpack("q", result)
        self.assertEqual(unpacked[0], 1000000000000)

    def test_longlong_negative(self):
        result = struct.pack("q", -1000000000000)
        unpacked = struct.unpack("q", result)
        self.assertEqual(unpacked[0], -1000000000000)

    def test_ulonglong_large(self):
        result = struct.pack("Q", 10000000000000)
        unpacked = struct.unpack("Q", result)
        self.assertEqual(unpacked[0], 10000000000000)

if __name__ == "__main__":
    unittest.main()
