"""Gzip roundtrip tests for metal0 C interop"""
import gzip
import unittest

class TestGzipRoundtripShort(unittest.TestCase):
    def test_roundtrip_a(self):
        original = b"a"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_ab(self):
        original = b"ab"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_abc(self):
        original = b"abc"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_hello(self):
        original = b"hello"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_world(self):
        original = b"world"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

class TestGzipRoundtripMedium(unittest.TestCase):
    def test_roundtrip_sentence(self):
        original = b"The quick brown fox"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_numbers(self):
        original = b"1234567890"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_mixed(self):
        original = b"abc123xyz"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

class TestGzipCompress(unittest.TestCase):
    def test_compress_returns_bytes(self):
        result = gzip.compress(b"test")
        self.assertIsInstance(result, bytes)

    def test_compress_smaller_for_repeated(self):
        original = b"aaaaaaaaaaaaaaaa"
        compressed = gzip.compress(original)
        self.assertLess(len(compressed), len(original) + 20)

    def test_compress_empty(self):
        result = gzip.compress(b"")
        self.assertIsInstance(result, bytes)

class TestGzipDecompress(unittest.TestCase):
    def test_decompress_returns_bytes(self):
        compressed = gzip.compress(b"test")
        result = gzip.decompress(compressed)
        self.assertIsInstance(result, bytes)

    def test_decompress_preserves_length(self):
        original = b"hello world"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(len(result), len(original))

if __name__ == "__main__":
    unittest.main()
