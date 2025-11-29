"""Hashlib algorithm tests for metal0 C interop"""
import hashlib
import unittest

class TestMd5Values(unittest.TestCase):
    def test_md5_hello(self):
        result = hashlib.md5(b"hello").hexdigest()
        self.assertEqual(result, "5d41402abc4b2a76b9719d911017c592")

    def test_md5_world(self):
        result = hashlib.md5(b"world").hexdigest()
        self.assertEqual(result, "7d793037a0760186574b0282f2f435e7")

    def test_md5_empty(self):
        result = hashlib.md5(b"").hexdigest()
        self.assertEqual(result, "d41d8cd98f00b204e9800998ecf8427e")

    def test_md5_abc(self):
        result = hashlib.md5(b"abc").hexdigest()
        self.assertEqual(result, "900150983cd24fb0d6963f7d28e17f72")

    def test_md5_test(self):
        result = hashlib.md5(b"test").hexdigest()
        self.assertEqual(result, "098f6bcd4621d373cade4e832627b4f6")

class TestSha1Values(unittest.TestCase):
    def test_sha1_hello(self):
        result = hashlib.sha1(b"hello").hexdigest()
        self.assertEqual(result, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_sha1_world(self):
        result = hashlib.sha1(b"world").hexdigest()
        self.assertEqual(result, "7c211433f02071597741e6ff5a8ea34789abbf43")

    def test_sha1_empty(self):
        result = hashlib.sha1(b"").hexdigest()
        self.assertEqual(result, "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    def test_sha1_abc(self):
        result = hashlib.sha1(b"abc").hexdigest()
        self.assertEqual(result, "a9993e364706816aba3e25717850c26c9cd0d89d")

class TestSha256Values(unittest.TestCase):
    def test_sha256_hello(self):
        result = hashlib.sha256(b"hello").hexdigest()
        self.assertEqual(result, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_sha256_world(self):
        result = hashlib.sha256(b"world").hexdigest()
        self.assertEqual(result, "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7")

    def test_sha256_empty(self):
        result = hashlib.sha256(b"").hexdigest()
        self.assertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    def test_sha256_abc(self):
        result = hashlib.sha256(b"abc").hexdigest()
        self.assertEqual(result, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

class TestSha512Values(unittest.TestCase):
    def test_sha512_hello(self):
        result = hashlib.sha512(b"hello").hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_world(self):
        result = hashlib.sha512(b"world").hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_empty(self):
        result = hashlib.sha512(b"").hexdigest()
        self.assertEqual(len(result), 128)

class TestHashConsistency(unittest.TestCase):
    def test_md5_consistent(self):
        a = hashlib.md5(b"test").hexdigest()
        b = hashlib.md5(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha1_consistent(self):
        a = hashlib.sha1(b"test").hexdigest()
        b = hashlib.sha1(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha256_consistent(self):
        a = hashlib.sha256(b"test").hexdigest()
        b = hashlib.sha256(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha512_consistent(self):
        a = hashlib.sha512(b"test").hexdigest()
        b = hashlib.sha512(b"test").hexdigest()
        self.assertEqual(a, b)

class TestUpdateMethod(unittest.TestCase):
    def test_md5_update_equals_direct(self):
        h = hashlib.md5()
        h.update(b"hello")
        a = h.hexdigest()
        b = hashlib.md5(b"hello").hexdigest()
        self.assertEqual(a, b)

    def test_sha256_update_equals_direct(self):
        h = hashlib.sha256()
        h.update(b"hello")
        a = h.hexdigest()
        b = hashlib.sha256(b"hello").hexdigest()
        self.assertEqual(a, b)

    def test_sha512_update_equals_direct(self):
        h = hashlib.sha512()
        h.update(b"hello")
        a = h.hexdigest()
        b = hashlib.sha512(b"hello").hexdigest()
        self.assertEqual(a, b)

class TestDigestLength(unittest.TestCase):
    def test_md5_digest_length(self):
        result = hashlib.md5(b"x").hexdigest()
        self.assertEqual(len(result), 32)

    def test_sha1_digest_length(self):
        result = hashlib.sha1(b"x").hexdigest()
        self.assertEqual(len(result), 40)

    def test_sha224_digest_length(self):
        result = hashlib.sha224(b"x").hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha256_digest_length(self):
        result = hashlib.sha256(b"x").hexdigest()
        self.assertEqual(len(result), 64)

    def test_sha384_digest_length(self):
        result = hashlib.sha384(b"x").hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha512_digest_length(self):
        result = hashlib.sha512(b"x").hexdigest()
        self.assertEqual(len(result), 128)

if __name__ == "__main__":
    unittest.main()
