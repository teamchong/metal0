"""Struct pack/unpack roundtrip tests for metal0 C interop"""
import struct
import unittest

class TestPackUnpackRoundtrip(unittest.TestCase):
    def test_pack_unpack_byte(self):
        data = struct.pack('b', 42)
        result = struct.unpack('b', data)
        self.assertEqual(result[0], 42)

    def test_pack_unpack_unsigned_byte(self):
        data = struct.pack('B', 200)
        result = struct.unpack('B', data)
        self.assertEqual(result[0], 200)

    def test_pack_unpack_short(self):
        data = struct.pack('h', 1000)
        result = struct.unpack('h', data)
        self.assertEqual(result[0], 1000)

    def test_pack_unpack_unsigned_short(self):
        data = struct.pack('H', 50000)
        result = struct.unpack('H', data)
        self.assertEqual(result[0], 50000)

    def test_pack_unpack_int(self):
        data = struct.pack('i', 100000)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], 100000)

    def test_pack_unpack_unsigned_int(self):
        data = struct.pack('I', 3000000000)
        result = struct.unpack('I', data)
        self.assertEqual(result[0], 3000000000)

    def test_pack_unpack_long(self):
        data = struct.pack('l', 100000)
        result = struct.unpack('l', data)
        self.assertEqual(result[0], 100000)

    def test_pack_unpack_unsigned_long(self):
        data = struct.pack('L', 3000000000)
        result = struct.unpack('L', data)
        self.assertEqual(result[0], 3000000000)

    def test_pack_unpack_longlong(self):
        data = struct.pack('q', 9000000000000)
        result = struct.unpack('q', data)
        self.assertEqual(result[0], 9000000000000)

    def test_pack_unpack_unsigned_longlong(self):
        data = struct.pack('Q', 9223372036854775807)
        result = struct.unpack('Q', data)
        self.assertEqual(result[0], 9223372036854775807)

class TestPackUnpackMultiple(unittest.TestCase):
    def test_pack_unpack_two_ints(self):
        data = struct.pack('ii', 10, 20)
        result = struct.unpack('ii', data)
        self.assertEqual(result[0], 10)
        self.assertEqual(result[1], 20)

    def test_pack_unpack_byte_short_int(self):
        data = struct.pack('bhi', 5, 1000, 50000)
        result = struct.unpack('bhi', data)
        self.assertEqual(result[0], 5)
        self.assertEqual(result[1], 1000)
        self.assertEqual(result[2], 50000)

    def test_pack_unpack_three_bytes(self):
        data = struct.pack('bbb', 1, 2, 3)
        result = struct.unpack('bbb', data)
        self.assertEqual(result[0], 1)
        self.assertEqual(result[1], 2)
        self.assertEqual(result[2], 3)

    def test_pack_unpack_two_shorts(self):
        data = struct.pack('hh', 100, 200)
        result = struct.unpack('hh', data)
        self.assertEqual(result[0], 100)
        self.assertEqual(result[1], 200)

class TestNativeEndian(unittest.TestCase):
    def test_native_int(self):
        data = struct.pack('@i', 12345)
        result = struct.unpack('@i', data)
        self.assertEqual(result[0], 12345)

    def test_native_short(self):
        data = struct.pack('@h', 5000)
        result = struct.unpack('@h', data)
        self.assertEqual(result[0], 5000)

    def test_native_byte(self):
        data = struct.pack('@b', 100)
        result = struct.unpack('@b', data)
        self.assertEqual(result[0], 100)

    def test_native_long(self):
        data = struct.pack('@l', 1000000)
        result = struct.unpack('@l', data)
        self.assertEqual(result[0], 1000000)

if __name__ == "__main__":
    unittest.main()
