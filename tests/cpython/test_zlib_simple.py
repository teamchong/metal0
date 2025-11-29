"""Simple zlib module tests for metal0"""
import zlib
import unittest

class TestZlibCompress(unittest.TestCase):
    def test_compress_decompress(self):
        data = b"hello world hello world hello world"
        compressed = zlib.compress(data)
        self.assertIsInstance(compressed, bytes)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_compress_empty(self):
        data = b""
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        self.assertEqual(decompressed, data)

    def test_crc32_hello(self):
        data = b"hello"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        crc = zlib.crc32(decompressed)
        self.assertIsInstance(crc, int)
        self.assertEqual(crc, 907060870)

    def test_adler32_hello(self):
        data = b"hello"
        compressed = zlib.compress(data)
        decompressed = zlib.decompress(compressed)
        adler = zlib.adler32(decompressed)
        self.assertIsInstance(adler, int)
        self.assertEqual(adler, 103547413)

if __name__ == "__main__":
    unittest.main()
