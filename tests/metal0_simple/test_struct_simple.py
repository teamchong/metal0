"""Comprehensive struct module tests for metal0"""
import struct
import unittest

class TestStructPack(unittest.TestCase):
    def test_pack_int(self):
        result = struct.pack('i', 42)
        self.assertEqual(len(result), 4)

    def test_pack_int_100(self):
        result = struct.pack('i', 100)
        self.assertEqual(len(result), 4)

    def test_pack_int_65(self):
        result = struct.pack('i', 65)
        self.assertEqual(len(result), 4)

    def test_pack_long(self):
        result = struct.pack('l', 100000)
        self.assertTrue(len(result) >= 4)

    def test_pack_int_zero(self):
        result = struct.pack('i', 0)
        self.assertEqual(len(result), 4)

    def test_pack_int_negative(self):
        result = struct.pack('i', -1)
        self.assertEqual(len(result), 4)

class TestStructUnpack(unittest.TestCase):
    def test_unpack_int(self):
        data = struct.pack('i', 42)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], 42)

    def test_unpack_int_100(self):
        data = struct.pack('i', 100)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], 100)

    def test_unpack_int_65(self):
        data = struct.pack('i', 65)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], 65)

class TestStructCalcsize(unittest.TestCase):
    def test_calcsize_int(self):
        size = struct.calcsize('i')
        self.assertEqual(size, 4)

    def test_calcsize_int_positive(self):
        size = struct.calcsize('i')
        self.assertTrue(size > 0)

    def test_calcsize_double(self):
        size = struct.calcsize('d')
        self.assertEqual(size, 8)

    def test_calcsize_float(self):
        size = struct.calcsize('f')
        self.assertEqual(size, 4)

class TestStructRoundtrip(unittest.TestCase):
    def test_roundtrip_int(self):
        original = 12345
        data = struct.pack('i', original)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], original)

    def test_roundtrip_negative(self):
        original = -999
        data = struct.pack('i', original)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], original)

    def test_roundtrip_255(self):
        original = 255
        data = struct.pack('i', original)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], original)

    def test_roundtrip_127(self):
        original = 127
        data = struct.pack('i', original)
        result = struct.unpack('i', data)
        self.assertEqual(result[0], original)

if __name__ == "__main__":
    unittest.main()
