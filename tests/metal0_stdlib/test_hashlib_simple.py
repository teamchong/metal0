"""Simple hashlib module tests for metal0"""
import hashlib
import unittest

class TestHashlibMd5(unittest.TestCase):
    def test_md5_exists(self):
        h = hashlib.md5(b"hello")
        self.assertIsNotNone(h)

    def test_md5_type(self):
        h = hashlib.md5(b"test")
        self.assertIsNotNone(h)

class TestHashlibSha1(unittest.TestCase):
    def test_sha1_exists(self):
        h = hashlib.sha1(b"hello")
        self.assertIsNotNone(h)

    def test_sha1_type(self):
        h = hashlib.sha1(b"test")
        self.assertIsNotNone(h)

class TestHashlibSha256(unittest.TestCase):
    def test_sha256_exists(self):
        h = hashlib.sha256(b"hello")
        self.assertIsNotNone(h)

    def test_sha256_type(self):
        h = hashlib.sha256(b"test")
        self.assertIsNotNone(h)

class TestHashlibSha512(unittest.TestCase):
    def test_sha512_exists(self):
        h = hashlib.sha512(b"hello")
        self.assertIsNotNone(h)

    def test_sha512_type(self):
        h = hashlib.sha512(b"test")
        self.assertIsNotNone(h)

if __name__ == "__main__":
    unittest.main()
