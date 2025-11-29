"""Comprehensive struct module tests for metal0 C interop"""
import struct
import unittest

class TestPackInt(unittest.TestCase):
    def test_pack_int_zero(self):
        result = struct.pack("i", 0)
        self.assertEqual(len(result), 4)

    def test_pack_int_one(self):
        result = struct.pack("i", 1)
        self.assertEqual(len(result), 4)

    def test_pack_int_negative(self):
        result = struct.pack("i", -1)
        self.assertEqual(len(result), 4)

    def test_pack_int_max(self):
        result = struct.pack("i", 2147483647)
        self.assertEqual(len(result), 4)

    def test_pack_int_min(self):
        result = struct.pack("i", -2147483648)
        self.assertEqual(len(result), 4)

class TestPackShort(unittest.TestCase):
    def test_pack_short_zero(self):
        result = struct.pack("h", 0)
        self.assertEqual(len(result), 2)

    def test_pack_short_one(self):
        result = struct.pack("h", 1)
        self.assertEqual(len(result), 2)

    def test_pack_short_negative(self):
        result = struct.pack("h", -1)
        self.assertEqual(len(result), 2)

    def test_pack_short_max(self):
        result = struct.pack("h", 32767)
        self.assertEqual(len(result), 2)

    def test_pack_short_min(self):
        result = struct.pack("h", -32768)
        self.assertEqual(len(result), 2)

class TestPackByte(unittest.TestCase):
    def test_pack_byte_zero(self):
        result = struct.pack("b", 0)
        self.assertEqual(len(result), 1)

    def test_pack_byte_one(self):
        result = struct.pack("b", 1)
        self.assertEqual(len(result), 1)

    def test_pack_byte_negative(self):
        result = struct.pack("b", -1)
        self.assertEqual(len(result), 1)

    def test_pack_byte_max(self):
        result = struct.pack("b", 127)
        self.assertEqual(len(result), 1)

    def test_pack_byte_min(self):
        result = struct.pack("b", -128)
        self.assertEqual(len(result), 1)

class TestPackUnsigned(unittest.TestCase):
    def test_pack_uint_zero(self):
        result = struct.pack("I", 0)
        self.assertEqual(len(result), 4)

    def test_pack_uint_one(self):
        result = struct.pack("I", 1)
        self.assertEqual(len(result), 4)

    def test_pack_uint_max(self):
        result = struct.pack("I", 4294967295)
        self.assertEqual(len(result), 4)

    def test_pack_ushort_zero(self):
        result = struct.pack("H", 0)
        self.assertEqual(len(result), 2)

    def test_pack_ushort_max(self):
        result = struct.pack("H", 65535)
        self.assertEqual(len(result), 2)

class TestPackFloat(unittest.TestCase):
    def test_pack_float_zero(self):
        result = struct.pack("f", 0.0)
        self.assertEqual(len(result), 4)

    def test_pack_float_one(self):
        result = struct.pack("f", 1.0)
        self.assertEqual(len(result), 4)

    def test_pack_float_negative(self):
        result = struct.pack("f", -1.0)
        self.assertEqual(len(result), 4)

    def test_pack_float_pi(self):
        result = struct.pack("f", 3.14159)
        self.assertEqual(len(result), 4)

class TestPackDouble(unittest.TestCase):
    def test_pack_double_zero(self):
        result = struct.pack("d", 0.0)
        self.assertEqual(len(result), 8)

    def test_pack_double_one(self):
        result = struct.pack("d", 1.0)
        self.assertEqual(len(result), 8)

    def test_pack_double_negative(self):
        result = struct.pack("d", -1.0)
        self.assertEqual(len(result), 8)

    def test_pack_double_pi(self):
        result = struct.pack("d", 3.141592653589793)
        self.assertEqual(len(result), 8)

class TestCalcsize(unittest.TestCase):
    def test_calcsize_int(self):
        self.assertEqual(struct.calcsize("i"), 4)

    def test_calcsize_short(self):
        self.assertEqual(struct.calcsize("h"), 2)

    def test_calcsize_byte(self):
        self.assertEqual(struct.calcsize("b"), 1)

    def test_calcsize_float(self):
        self.assertEqual(struct.calcsize("f"), 4)

    def test_calcsize_double(self):
        self.assertEqual(struct.calcsize("d"), 8)

    def test_calcsize_uint(self):
        self.assertEqual(struct.calcsize("I"), 4)

    def test_calcsize_ushort(self):
        self.assertEqual(struct.calcsize("H"), 2)

    def test_calcsize_ubyte(self):
        self.assertEqual(struct.calcsize("B"), 1)

class TestUnpackInt(unittest.TestCase):
    def test_unpack_int_zero(self):
        packed = struct.pack("i", 0)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 0)

    def test_unpack_int_one(self):
        packed = struct.pack("i", 1)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 1)

    def test_unpack_int_negative(self):
        packed = struct.pack("i", -1)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], -1)

    def test_unpack_int_large(self):
        packed = struct.pack("i", 12345678)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 12345678)

class TestUnpackShort(unittest.TestCase):
    def test_unpack_short_zero(self):
        packed = struct.pack("h", 0)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 0)

    def test_unpack_short_one(self):
        packed = struct.pack("h", 1)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 1)

    def test_unpack_short_positive(self):
        packed = struct.pack("h", 100)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 100)

class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_int_zero(self):
        packed = struct.pack("i", 0)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 0)

    def test_roundtrip_int_positive(self):
        packed = struct.pack("i", 12345)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 12345)

    def test_roundtrip_int_large(self):
        packed = struct.pack("i", 2147483647)
        result = struct.unpack("i", packed)
        self.assertEqual(result[0], 2147483647)

    def test_roundtrip_short_zero(self):
        packed = struct.pack("h", 0)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 0)

    def test_roundtrip_short_positive(self):
        packed = struct.pack("h", 1234)
        result = struct.unpack("h", packed)
        self.assertEqual(result[0], 1234)

    def test_roundtrip_byte_zero(self):
        packed = struct.pack("b", 0)
        result = struct.unpack("b", packed)
        self.assertEqual(result[0], 0)

    def test_roundtrip_byte_positive(self):
        packed = struct.pack("b", 100)
        result = struct.unpack("b", packed)
        self.assertEqual(result[0], 100)

if __name__ == "__main__":
    unittest.main()
