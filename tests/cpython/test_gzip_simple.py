"""Simple gzip module tests for metal0"""
import gzip
import unittest

class TestGzipBasic(unittest.TestCase):
    def test_compress_decompress(self):
        data = b"hello world hello world hello world"
        compressed = gzip.compress(data)
        self.assertIsInstance(compressed, bytes)
        # Gzip header starts with 0x1f 0x8b
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_empty(self):
        data = b""
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_small(self):
        data = b"x"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_binary(self):
        # Binary data with null bytes
        data = b"\x00\x01\x02\x03\xff\xfe\xfd"
        compressed = gzip.compress(data)
        decompressed = gzip.decompress(compressed)
        self.assertEqual(decompressed, data)

if __name__ == "__main__":
    unittest.main()
