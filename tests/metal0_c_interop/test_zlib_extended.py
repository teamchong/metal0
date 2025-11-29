"""Extended zlib module tests for metal0 C interop"""
import zlib
import unittest

class TestCompressDecompress(unittest.TestCase):
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

    def test_compress_long(self):
        data = b"a" * 1000
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_pattern(self):
        data = b"abcd" * 100
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_sentence(self):
        data = b"The quick brown fox jumps over the lazy dog"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestCrc32Extended(unittest.TestCase):
    def test_crc32_hello(self):
        result = zlib.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = zlib.crc32(b"world")
        self.assertTrue(result > 0)

    def test_crc32_empty(self):
        result = zlib.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_abc(self):
        result = zlib.crc32(b"abc")
        self.assertTrue(result > 0)

    def test_crc32_long(self):
        result = zlib.crc32(b"a" * 1000)
        self.assertTrue(result > 0)

    def test_crc32_same_input(self):
        a = zlib.crc32(b"test")
        b = zlib.crc32(b"test")
        self.assertEqual(a, b)

class TestAdler32Extended(unittest.TestCase):
    def test_adler32_hello(self):
        result = zlib.adler32(b"hello")
        self.assertEqual(result, 103547413)

    def test_adler32_world(self):
        result = zlib.adler32(b"world")
        self.assertTrue(result > 0)

    def test_adler32_empty(self):
        result = zlib.adler32(b"")
        self.assertEqual(result, 1)

    def test_adler32_abc(self):
        result = zlib.adler32(b"abc")
        self.assertTrue(result > 0)

    def test_adler32_long(self):
        result = zlib.adler32(b"a" * 1000)
        self.assertTrue(result > 0)

    def test_adler32_same_input(self):
        a = zlib.adler32(b"test")
        b = zlib.adler32(b"test")
        self.assertEqual(a, b)

class TestCompressRatio(unittest.TestCase):
    def test_repeated_compresses(self):
        data = b"a" * 10000
        compressed = zlib.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_pattern_compresses(self):
        data = b"abcd" * 1000
        compressed = zlib.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_random_like_worse(self):
        data = b"The quick brown fox jumps over the lazy dog"
        compressed = zlib.compress(data)
        # Short random-like data may not compress much
        self.assertTrue(len(compressed) > 0)

class TestDecompressConsistency(unittest.TestCase):
    def test_decompress_consistent(self):
        data = b"test data for consistency"
        compressed = zlib.compress(data)
        a = zlib.decompress(compressed)
        b = zlib.decompress(compressed)
        self.assertEqual(a, b)

    def test_decompress_length(self):
        data = b"x" * 100
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(len(decompressed), 100)

class TestEdgeCases(unittest.TestCase):
    def test_compress_single_byte(self):
        data = b"x"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_numbers(self):
        data = b"1234567890"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_newlines(self):
        data = b"line1\nline2\nline3"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_tabs(self):
        data = b"col1\tcol2\tcol3"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

if __name__ == "__main__":
    unittest.main()
