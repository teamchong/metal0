"""Gzip length and type tests for metal0 C interop"""
import gzip
import unittest

class TestGzipCompressLengths(unittest.TestCase):
    def test_compress_empty_returns_bytes(self):
        result = gzip.compress(b"")
        self.assertIsInstance(result, bytes)

    def test_compress_a_returns_bytes(self):
        result = gzip.compress(b"a")
        self.assertIsInstance(result, bytes)

    def test_compress_hello_returns_bytes(self):
        result = gzip.compress(b"hello")
        self.assertIsInstance(result, bytes)

    def test_compress_long_returns_bytes(self):
        result = gzip.compress(b"hello world this is a test")
        self.assertIsInstance(result, bytes)

class TestGzipDecompressLengths(unittest.TestCase):
    def test_decompress_returns_bytes(self):
        compressed = gzip.compress(b"test")
        result = gzip.decompress(compressed)
        self.assertIsInstance(result, bytes)

    def test_decompress_hello_returns_bytes(self):
        compressed = gzip.compress(b"hello")
        result = gzip.decompress(compressed)
        self.assertIsInstance(result, bytes)

    def test_decompress_long_returns_bytes(self):
        compressed = gzip.compress(b"hello world this is a test")
        result = gzip.decompress(compressed)
        self.assertIsInstance(result, bytes)

class TestGzipRoundtripContent(unittest.TestCase):
    def test_roundtrip_empty(self):
        original = b""
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_space(self):
        original = b" "
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_newline(self):
        original = b"\n"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

    def test_roundtrip_tab(self):
        original = b"\t"
        compressed = gzip.compress(original)
        result = gzip.decompress(compressed)
        self.assertEqual(result, original)

class TestGzipCompression(unittest.TestCase):
    def test_repeated_data_compresses(self):
        original = b"aaaaaaaaaaaaaaaa"
        compressed = gzip.compress(original)
        self.assertLess(len(compressed), len(original) + 20)

    def test_random_looking_data(self):
        original = b"qwertyuiopasdfgh"
        compressed = gzip.compress(original)
        self.assertIsInstance(compressed, bytes)

if __name__ == "__main__":
    unittest.main()
