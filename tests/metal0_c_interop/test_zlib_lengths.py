"""Zlib compression with various data lengths for metal0 C interop"""
import zlib
import unittest

class TestCompressShort(unittest.TestCase):
    def test_compress_1_byte(self):
        result = zlib.compress(b"a")
        self.assertIsInstance(result, bytes)

    def test_compress_2_bytes(self):
        result = zlib.compress(b"ab")
        self.assertIsInstance(result, bytes)

    def test_compress_5_bytes(self):
        result = zlib.compress(b"hello")
        self.assertIsInstance(result, bytes)

    def test_compress_10_bytes(self):
        result = zlib.compress(b"helloworld")
        self.assertIsInstance(result, bytes)

class TestCompressMedium(unittest.TestCase):
    def test_compress_20_bytes(self):
        result = zlib.compress(b"12345678901234567890")
        self.assertIsInstance(result, bytes)

    def test_compress_50_bytes(self):
        data = b"a" * 50
        result = zlib.compress(data)
        self.assertIsInstance(result, bytes)

    def test_compress_100_bytes(self):
        data = b"x" * 100
        result = zlib.compress(data)
        self.assertIsInstance(result, bytes)

class TestDecompressShort(unittest.TestCase):
    def test_decompress_hello(self):
        compressed = zlib.compress(b"hello")
        result = zlib.decompress(compressed)
        self.assertEqual(result, b"hello")

    def test_decompress_world(self):
        compressed = zlib.compress(b"world")
        result = zlib.decompress(compressed)
        self.assertEqual(result, b"world")

    def test_decompress_abc(self):
        compressed = zlib.compress(b"abc")
        result = zlib.decompress(compressed)
        self.assertEqual(result, b"abc")

class TestDecompressMedium(unittest.TestCase):
    def test_decompress_sentence(self):
        original = b"The quick brown fox"
        compressed = zlib.compress(original)
        result = zlib.decompress(compressed)
        self.assertEqual(result, original)

    def test_decompress_numbers(self):
        original = b"1234567890"
        compressed = zlib.compress(original)
        result = zlib.decompress(compressed)
        self.assertEqual(result, original)

class TestCrc32Values(unittest.TestCase):
    def test_crc32_a(self):
        result = zlib.crc32(b"a")
        self.assertEqual(result, 3904355907)

    def test_crc32_ab(self):
        result = zlib.crc32(b"ab")
        self.assertEqual(result, 2659403885)

    def test_crc32_abc(self):
        result = zlib.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_abcd(self):
        result = zlib.crc32(b"abcd")
        self.assertEqual(result, 3984772369)

class TestAdler32Values(unittest.TestCase):
    def test_adler32_a(self):
        result = zlib.adler32(b"a")
        self.assertEqual(result, 6422626)

    def test_adler32_ab(self):
        result = zlib.adler32(b"ab")
        self.assertEqual(result, 19267780)

    def test_adler32_abc(self):
        result = zlib.adler32(b"abc")
        self.assertEqual(result, 38600999)

    def test_adler32_abcd(self):
        result = zlib.adler32(b"abcd")
        self.assertEqual(result, 64487819)

if __name__ == "__main__":
    unittest.main()
