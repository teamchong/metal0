"""Zlib CRC32 and Adler32 tests for metal0 C interop"""
import zlib
import unittest

class TestCrc32Extended(unittest.TestCase):
    def test_crc32_empty(self):
        result = zlib.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_a(self):
        result = zlib.crc32(b"a")
        self.assertEqual(result, 3904355907)

    def test_crc32_ab(self):
        result = zlib.crc32(b"ab")
        self.assertEqual(result, 2659403885)

    def test_crc32_abc(self):
        result = zlib.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_hello(self):
        result = zlib.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = zlib.crc32(b"world")
        self.assertEqual(result, 980881731)

    def test_crc32_123(self):
        result = zlib.crc32(b"123")
        self.assertEqual(result, 2286445522)

    def test_crc32_test(self):
        result = zlib.crc32(b"test")
        self.assertEqual(result, 3632233996)

class TestAdler32Extended(unittest.TestCase):
    def test_adler32_empty(self):
        result = zlib.adler32(b"")
        self.assertEqual(result, 1)

    def test_adler32_a(self):
        result = zlib.adler32(b"a")
        self.assertEqual(result, 6422626)

    def test_adler32_ab(self):
        result = zlib.adler32(b"ab")
        self.assertEqual(result, 19267780)

    def test_adler32_abc(self):
        result = zlib.adler32(b"abc")
        self.assertEqual(result, 38600999)

    def test_adler32_hello(self):
        result = zlib.adler32(b"hello")
        self.assertEqual(result, 103547413)

    def test_adler32_world(self):
        result = zlib.adler32(b"world")
        self.assertEqual(result, 111542825)

    def test_adler32_123(self):
        result = zlib.adler32(b"123")
        self.assertEqual(result, 19726487)

    def test_adler32_test(self):
        result = zlib.adler32(b"test")
        self.assertEqual(result, 73204161)

class TestChecksumTypes(unittest.TestCase):
    def test_crc32_returns_int(self):
        result = zlib.crc32(b"test")
        self.assertIsInstance(result, int)

    def test_adler32_returns_int(self):
        result = zlib.adler32(b"test")
        self.assertIsInstance(result, int)

    def test_crc32_positive(self):
        result = zlib.crc32(b"test")
        self.assertGreaterEqual(result, 0)

    def test_adler32_positive(self):
        result = zlib.adler32(b"test")
        self.assertGreaterEqual(result, 0)

if __name__ == "__main__":
    unittest.main()
