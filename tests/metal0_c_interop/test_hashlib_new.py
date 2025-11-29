"""Hashlib new() function tests for metal0 C interop"""
import hashlib
import unittest

class TestNewMd5(unittest.TestCase):
    def test_new_md5_hello(self):
        h = hashlib.new("md5")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_new_md5_world(self):
        h = hashlib.new("md5")
        h.update(b"world")
        self.assertEqual(h.hexdigest(), "7d793037a0760186574b0282f2f435e7")

    def test_new_md5_empty(self):
        h = hashlib.new("md5")
        h.update(b"")
        self.assertEqual(h.hexdigest(), "d41d8cd98f00b204e9800998ecf8427e")

    def test_new_md5_abc(self):
        h = hashlib.new("md5")
        h.update(b"abc")
        self.assertEqual(h.hexdigest(), "900150983cd24fb0d6963f7d28e17f72")

class TestNewSha1(unittest.TestCase):
    def test_new_sha1_hello(self):
        h = hashlib.new("sha1")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_new_sha1_world(self):
        h = hashlib.new("sha1")
        h.update(b"world")
        self.assertEqual(h.hexdigest(), "7c211433f02071597741e6ff5a8ea34789abbf43")

    def test_new_sha1_empty(self):
        h = hashlib.new("sha1")
        h.update(b"")
        self.assertEqual(h.hexdigest(), "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    def test_new_sha1_abc(self):
        h = hashlib.new("sha1")
        h.update(b"abc")
        self.assertEqual(h.hexdigest(), "a9993e364706816aba3e25717850c26c9cd0d89d")

class TestNewSha256(unittest.TestCase):
    def test_new_sha256_hello(self):
        h = hashlib.new("sha256")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_new_sha256_world(self):
        h = hashlib.new("sha256")
        h.update(b"world")
        self.assertEqual(h.hexdigest(), "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7")

    def test_new_sha256_empty(self):
        h = hashlib.new("sha256")
        h.update(b"")
        self.assertEqual(h.hexdigest(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    def test_new_sha256_abc(self):
        h = hashlib.new("sha256")
        h.update(b"abc")
        self.assertEqual(h.hexdigest(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

class TestNewSha512(unittest.TestCase):
    def test_new_sha512_hello_len(self):
        h = hashlib.new("sha512")
        h.update(b"hello")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

    def test_new_sha512_world_len(self):
        h = hashlib.new("sha512")
        h.update(b"world")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

    def test_new_sha512_empty_len(self):
        h = hashlib.new("sha512")
        h.update(b"")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

class TestNewConsistency(unittest.TestCase):
    def test_new_md5_equals_direct(self):
        h = hashlib.new("md5")
        h.update(b"test")
        a = h.hexdigest()
        b = hashlib.md5(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_new_sha1_equals_direct(self):
        h = hashlib.new("sha1")
        h.update(b"test")
        a = h.hexdigest()
        b = hashlib.sha1(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_new_sha256_equals_direct(self):
        h = hashlib.new("sha256")
        h.update(b"test")
        a = h.hexdigest()
        b = hashlib.sha256(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_new_sha512_equals_direct(self):
        h = hashlib.new("sha512")
        h.update(b"test")
        a = h.hexdigest()
        b = hashlib.sha512(b"test").hexdigest()
        self.assertEqual(a, b)

if __name__ == "__main__":
    unittest.main()
