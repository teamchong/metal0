"""Comprehensive gzip module tests for metal0 C interop"""
import gzip
import unittest

class TestCompressBasic(unittest.TestCase):
    def test_compress_hello(self):
        data = b"hello"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_world(self):
        data = b"world"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_empty(self):
        data = b""
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_abc(self):
        data = b"abc"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_digits(self):
        data = b"123456789"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCompressLonger(unittest.TestCase):
    def test_compress_sentence(self):
        data = b"The quick brown fox jumps over the lazy dog"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_repeated(self):
        data = b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_pattern(self):
        data = b"abcabcabcabcabcabcabcabcabcabc"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_mixed(self):
        data = b"Hello World 123 !@#"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCompressBinary(unittest.TestCase):
    def test_compress_null_bytes(self):
        data = b"\x00\x00\x00\x00"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_binary_seq(self):
        data = b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_high_bytes(self):
        data = b"\xff\xfe\xfd\xfc"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCompressRatio(unittest.TestCase):
    def test_repeated_compresses_well(self):
        data = b"a" * 1000
        compressed = gzip.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_pattern_compresses_well(self):
        data = b"abc" * 100
        compressed = gzip.compress(data)
        self.assertLess(len(compressed), len(data))

class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_short(self):
        data = b"x"
        self.assertEqual(gzip.decompress(gzip.compress(data)), data)

    def test_roundtrip_medium(self):
        data = b"medium length string for testing"
        self.assertEqual(gzip.decompress(gzip.compress(data)), data)

    def test_roundtrip_long(self):
        data = b"long" * 100
        self.assertEqual(gzip.decompress(gzip.compress(data)), data)

    def test_roundtrip_newlines(self):
        data = b"line1\nline2\nline3"
        self.assertEqual(gzip.decompress(gzip.compress(data)), data)

    def test_roundtrip_tabs(self):
        data = b"col1\tcol2\tcol3"
        self.assertEqual(gzip.decompress(gzip.compress(data)), data)

class TestConsistency(unittest.TestCase):
    def test_compress_consistent(self):
        data = b"test data"
        a = gzip.decompress(gzip.compress(data))
        b = gzip.decompress(gzip.compress(data))
        self.assertEqual(a, b)

    def test_decompress_consistent(self):
        data = b"test data"
        compressed = gzip.compress(data)
        a = gzip.decompress(compressed)
        b = gzip.decompress(compressed)
        self.assertEqual(a, b)

if __name__ == "__main__":
    unittest.main()
