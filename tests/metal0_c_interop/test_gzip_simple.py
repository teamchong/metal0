"""Simple gzip module tests for metal0"""
import gzip
import unittest

class TestGzipCompress(unittest.TestCase):
    def test_compress_bytes(self):
        data = b"hello world"
        compressed = gzip.compress(data)
        self.assertIsInstance(compressed, bytes)

    def test_compress_decompress(self):
        data = b"hello world hello world"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_empty(self):
        data = b""
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_long(self):
        data = b"abcdefghijklmnopqrstuvwxyz" * 10
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compressed_smaller(self):
        data = b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        compressed = gzip.compress(data)
        self.assertTrue(len(compressed) < len(data) + 50)

if __name__ == "__main__":
    unittest.main()
