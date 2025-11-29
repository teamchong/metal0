"""Extended gzip module tests for metal0 C interop"""
import gzip
import unittest

class TestGzipCompressBasic(unittest.TestCase):
    def test_compress_hello(self):
        data = b"hello"
        compressed = gzip.compress(data)
        self.assertTrue(len(compressed) > 0)

    def test_compress_world(self):
        data = b"world"
        compressed = gzip.compress(data)
        self.assertTrue(len(compressed) > 0)

    def test_compress_empty(self):
        data = b""
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_single(self):
        data = b"x"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestGzipDecompressBasic(unittest.TestCase):
    def test_decompress_hello(self):
        data = b"hello"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_decompress_world(self):
        data = b"world"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_decompress_abc(self):
        data = b"abc"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

class TestGzipRoundtrip(unittest.TestCase):
    def test_roundtrip_sentence(self):
        data = b"The quick brown fox jumps over the lazy dog"
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_roundtrip_numbers(self):
        data = b"1234567890"
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_roundtrip_repeated(self):
        data = b"a" * 100
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_roundtrip_pattern(self):
        data = b"abcd" * 50
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_roundtrip_spaces(self):
        data = b"hello world test"
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

class TestGzipCompression(unittest.TestCase):
    def test_repeated_compresses_well(self):
        data = b"a" * 1000
        compressed = gzip.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_pattern_compresses_well(self):
        data = b"abcd" * 250
        compressed = gzip.compress(data)
        self.assertLess(len(compressed), len(data))

    def test_long_compresses(self):
        data = b"x" * 10000
        compressed = gzip.compress(data)
        self.assertLess(len(compressed), len(data))

class TestGzipConsistency(unittest.TestCase):
    def test_compress_consistent(self):
        data = b"consistent test data"
        a = gzip.decompress(gzip.compress(data))
        b = gzip.decompress(gzip.compress(data))
        self.assertEqual(a, b)

    def test_decompress_consistent(self):
        data = b"test"
        compressed = gzip.compress(data)
        a = gzip.decompress(compressed)
        b = gzip.decompress(compressed)
        self.assertEqual(a, b)

class TestGzipLongData(unittest.TestCase):
    def test_long_text(self):
        data = b"long text data " * 100
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_long_repeated(self):
        data = b"z" * 5000
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

    def test_long_pattern(self):
        data = b"xyz" * 1000
        result = gzip.decompress(gzip.compress(data))
        self.assertEqual(result, data)

if __name__ == "__main__":
    unittest.main()
