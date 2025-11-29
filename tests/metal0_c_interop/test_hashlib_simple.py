"""Simple hashlib module tests for metal0"""
import hashlib
import unittest

class TestHashlibMd5(unittest.TestCase):
    def test_md5_hello(self):
        result = hashlib.md5(b"hello").hexdigest()
        self.assertEqual(result, "5d41402abc4b2a76b9719d911017c592")

    def test_md5_empty(self):
        result = hashlib.md5(b"").hexdigest()
        self.assertEqual(result, "d41d8cd98f00b204e9800998ecf8427e")

class TestHashlibSha1(unittest.TestCase):
    def test_sha1_hello(self):
        result = hashlib.sha1(b"hello").hexdigest()
        self.assertEqual(result, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_sha1_empty(self):
        result = hashlib.sha1(b"").hexdigest()
        self.assertEqual(result, "da39a3ee5e6b4b0d3255bfef95601890afd80709")

class TestHashlibSha256(unittest.TestCase):
    def test_sha256_hello(self):
        result = hashlib.sha256(b"hello").hexdigest()
        self.assertEqual(result, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_sha256_empty(self):
        result = hashlib.sha256(b"").hexdigest()
        self.assertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

class TestHashlibSha512(unittest.TestCase):
    def test_sha512_hello(self):
        result = hashlib.sha512(b"hello").hexdigest()
        # SHA512 of "hello" - 128 hex chars
        self.assertEqual(len(result), 128)

    def test_sha512_empty(self):
        result = hashlib.sha512(b"").hexdigest()
        self.assertEqual(len(result), 128)

if __name__ == "__main__":
    unittest.main()
