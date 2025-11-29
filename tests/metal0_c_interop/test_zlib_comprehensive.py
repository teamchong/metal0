"""Comprehensive zlib module tests for metal0 C interop"""
import zlib
import unittest

class TestCompressBasic(unittest.TestCase):
    def test_compress_hello(self):
        data = b"hello"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_world(self):
        data = b"world"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_empty(self):
        data = b""
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_abc(self):
        data = b"abc"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_digits(self):
        data = b"123456789"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCompressLonger(unittest.TestCase):
    def test_compress_sentence(self):
        data = b"The quick brown fox jumps over the lazy dog"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_repeated(self):
        data = b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_pattern(self):
        data = b"abcabcabcabcabcabcabcabcabcabc"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_mixed(self):
        data = b"Hello World 123 !@#"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCompressBinary(unittest.TestCase):
    def test_compress_null_bytes(self):
        data = b"\x00\x00\x00\x00"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_binary_sequence(self):
        data = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_high_bytes(self):
        data = b"\xff\xfe\xfd\xfc"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCrc32Basic(unittest.TestCase):
    def test_crc32_hello(self):
        result = zlib.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = zlib.crc32(b"world")
        self.assertEqual(result, 980881731)

    def test_crc32_empty(self):
        result = zlib.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_abc(self):
        result = zlib.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_digits(self):
        result = zlib.crc32(b"123456789")
        self.assertEqual(result, 3421780262)

class TestCrc32Consistency(unittest.TestCase):
    def test_crc32_consistent_hello(self):
        a = zlib.crc32(b"hello")
        b = zlib.crc32(b"hello")
        self.assertEqual(a, b)

    def test_crc32_consistent_world(self):
        a = zlib.crc32(b"world")
        b = zlib.crc32(b"world")
        self.assertEqual(a, b)

    def test_crc32_different(self):
        a = zlib.crc32(b"hello")
        b = zlib.crc32(b"world")
        self.assertNotEqual(a, b)

class TestAdler32Basic(unittest.TestCase):
    def test_adler32_hello(self):
        result = zlib.adler32(b"hello")
        self.assertEqual(result, 103547413)

    def test_adler32_world(self):
        result = zlib.adler32(b"world")
        self.assertEqual(result, 111542825)

    def test_adler32_empty(self):
        result = zlib.adler32(b"")
        self.assertEqual(result, 1)

    def test_adler32_abc(self):
        result = zlib.adler32(b"abc")
        self.assertEqual(result, 38600999)

    def test_adler32_digits(self):
        result = zlib.adler32(b"123456789")
        self.assertEqual(result, 152961502)

class TestAdler32Consistency(unittest.TestCase):
    def test_adler32_consistent_hello(self):
        a = zlib.adler32(b"hello")
        b = zlib.adler32(b"hello")
        self.assertEqual(a, b)

    def test_adler32_consistent_world(self):
        a = zlib.adler32(b"world")
        b = zlib.adler32(b"world")
        self.assertEqual(a, b)

    def test_adler32_different(self):
        a = zlib.adler32(b"hello")
        b = zlib.adler32(b"world")
        self.assertNotEqual(a, b)

class TestCompressRatio(unittest.TestCase):
    def test_repeated_compresses_well(self):
        data = b"a" * 1000
        compressed = zlib.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_pattern_compresses_well(self):
        data = b"abc" * 100
        compressed = zlib.compress(data)
        self.assertLess(len(compressed), len(data))

class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_short(self):
        data = b"x"
        self.assertEqual(zlib.decompress(zlib.compress(data)), data)

    def test_roundtrip_medium(self):
        data = b"medium length string for testing"
        self.assertEqual(zlib.decompress(zlib.compress(data)), data)

    def test_roundtrip_long(self):
        data = b"long" * 100
        self.assertEqual(zlib.decompress(zlib.compress(data)), data)

if __name__ == "__main__":
    unittest.main()
