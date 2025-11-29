"""Struct unpack C interop tests"""
import struct
import unittest

class TestUnpackByte(unittest.TestCase):
    def test_unpack_byte_0(self):
        result = struct.unpack('b', b'\x00')
        self.assertEqual(result[0], 0)

    def test_unpack_byte_1(self):
        result = struct.unpack('b', b'\x01')
        self.assertEqual(result[0], 1)

    def test_unpack_byte_127(self):
        result = struct.unpack('b', b'\x7f')
        self.assertEqual(result[0], 127)

    def test_unpack_byte_neg1(self):
        result = struct.unpack('b', b'\xff')
        self.assertEqual(result[0], -1)

    def test_unpack_byte_neg128(self):
        result = struct.unpack('b', b'\x80')
        self.assertEqual(result[0], -128)

class TestUnpackUnsignedByte(unittest.TestCase):
    def test_unpack_ubyte_0(self):
        result = struct.unpack('B', b'\x00')
        self.assertEqual(result[0], 0)

    def test_unpack_ubyte_1(self):
        result = struct.unpack('B', b'\x01')
        self.assertEqual(result[0], 1)

    def test_unpack_ubyte_127(self):
        result = struct.unpack('B', b'\x7f')
        self.assertEqual(result[0], 127)

    def test_unpack_ubyte_255(self):
        result = struct.unpack('B', b'\xff')
        self.assertEqual(result[0], 255)

class TestUnpackRoundtrip(unittest.TestCase):
    def test_roundtrip_byte(self):
        packed = struct.pack('b', 42)
        result = struct.unpack('b', packed)
        self.assertEqual(result[0], 42)

    def test_roundtrip_ubyte(self):
        packed = struct.pack('B', 200)
        result = struct.unpack('B', packed)
        self.assertEqual(result[0], 200)

    def test_roundtrip_short(self):
        packed = struct.pack('h', 1000)
        result = struct.unpack('h', packed)
        self.assertEqual(result[0], 1000)

    def test_roundtrip_int(self):
        packed = struct.pack('i', 100000)
        result = struct.unpack('i', packed)
        self.assertEqual(result[0], 100000)

    def test_roundtrip_long(self):
        packed = struct.pack('l', 100000)
        result = struct.unpack('l', packed)
        self.assertEqual(result[0], 100000)

    def test_roundtrip_longlong(self):
        packed = struct.pack('q', 9000000000000)
        result = struct.unpack('q', packed)
        self.assertEqual(result[0], 9000000000000)

class TestUnpackMultiple(unittest.TestCase):
    def test_unpack_two_bytes(self):
        packed = struct.pack('bb', 1, 2)
        result = struct.unpack('bb', packed)
        self.assertEqual(result[0], 1)
        self.assertEqual(result[1], 2)

    def test_unpack_two_shorts(self):
        packed = struct.pack('hh', 100, 200)
        result = struct.unpack('hh', packed)
        self.assertEqual(result[0], 100)
        self.assertEqual(result[1], 200)

    def test_unpack_two_ints(self):
        packed = struct.pack('ii', 10, 20)
        result = struct.unpack('ii', packed)
        self.assertEqual(result[0], 10)
        self.assertEqual(result[1], 20)

if __name__ == "__main__":
    unittest.main()
