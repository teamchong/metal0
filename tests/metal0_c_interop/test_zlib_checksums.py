"""Zlib checksum tests (crc32/adler32) for metal0 C interop"""
import zlib
import unittest

class TestCrc32Basic(unittest.TestCase):
    def test_crc32_hello(self):
        result = zlib.crc32(b"hello")
        self.assertEqual(result, 907060870)

    def test_crc32_world(self):
        result = zlib.crc32(b"world")
        self.assertEqual(result, 980881731)

    def test_crc32_empty(self):
        result = zlib.crc32(b"")
        self.assertEqual(result, 0)

    def test_crc32_abc(self):
        result = zlib.crc32(b"abc")
        self.assertEqual(result, 891568578)

    def test_crc32_test(self):
        result = zlib.crc32(b"test")
        self.assertEqual(result, 3632233996)

class TestAdler32Basic(unittest.TestCase):
    def test_adler32_hello(self):
        result = zlib.adler32(b"hello")
        self.assertEqual(result, 103547413)

    def test_adler32_world(self):
        result = zlib.adler32(b"world")
        self.assertEqual(result, 111542825)

    def test_adler32_empty(self):
        result = zlib.adler32(b"")
        self.assertEqual(result, 1)

    def test_adler32_abc(self):
        result = zlib.adler32(b"abc")
        self.assertEqual(result, 38600999)

    def test_adler32_test(self):
        result = zlib.adler32(b"test")
        self.assertEqual(result, 73204161)

class TestCrc32Long(unittest.TestCase):
    def test_crc32_repeated_a(self):
        result = zlib.crc32(b"a" * 100)
        self.assertTrue(result > 0)

    def test_crc32_repeated_x(self):
        result = zlib.crc32(b"x" * 100)
        self.assertTrue(result > 0)

    def test_crc32_pattern(self):
        result = zlib.crc32(b"abcd" * 25)
        self.assertTrue(result > 0)

    def test_crc32_sentence(self):
        result = zlib.crc32(b"The quick brown fox jumps over the lazy dog")
        self.assertTrue(result > 0)

class TestAdler32Long(unittest.TestCase):
    def test_adler32_repeated_a(self):
        result = zlib.adler32(b"a" * 100)
        self.assertTrue(result > 0)

    def test_adler32_repeated_x(self):
        result = zlib.adler32(b"x" * 100)
        self.assertTrue(result > 0)

    def test_adler32_pattern(self):
        result = zlib.adler32(b"abcd" * 25)
        self.assertTrue(result > 0)

    def test_adler32_sentence(self):
        result = zlib.adler32(b"The quick brown fox jumps over the lazy dog")
        self.assertTrue(result > 0)

class TestChecksumConsistency(unittest.TestCase):
    def test_crc32_consistent(self):
        a = zlib.crc32(b"consistency test")
        b = zlib.crc32(b"consistency test")
        self.assertEqual(a, b)

    def test_adler32_consistent(self):
        a = zlib.adler32(b"consistency test")
        b = zlib.adler32(b"consistency test")
        self.assertEqual(a, b)

    def test_crc32_different_input(self):
        a = zlib.crc32(b"hello")
        b = zlib.crc32(b"world")
        self.assertNotEqual(a, b)

    def test_adler32_different_input(self):
        a = zlib.adler32(b"hello")
        b = zlib.adler32(b"world")
        self.assertNotEqual(a, b)

class TestChecksumTypes(unittest.TestCase):
    def test_crc32_returns_int(self):
        result = zlib.crc32(b"test")
        self.assertTrue(result >= 0)

    def test_adler32_returns_int(self):
        result = zlib.adler32(b"test")
        self.assertTrue(result >= 0)

    def test_crc32_positive(self):
        result = zlib.crc32(b"x")
        self.assertTrue(result >= 0)

    def test_adler32_positive(self):
        result = zlib.adler32(b"x")
        self.assertTrue(result >= 0)

if __name__ == "__main__":
    unittest.main()
