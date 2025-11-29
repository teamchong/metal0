"""Comprehensive hashlib module tests for metal0 C interop"""
import hashlib
import unittest

class TestMd5Basic(unittest.TestCase):
    def test_md5_hello(self):
        self.assertEqual(hashlib.md5(b"hello").hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_md5_empty(self):
        self.assertEqual(hashlib.md5(b"").hexdigest(), "d41d8cd98f00b204e9800998ecf8427e")

    def test_md5_world(self):
        self.assertEqual(hashlib.md5(b"world").hexdigest(), "7d793037a0760186574b0282f2f435e7")

    def test_md5_abc(self):
        self.assertEqual(hashlib.md5(b"abc").hexdigest(), "900150983cd24fb0d6963f7d28e17f72")

    def test_md5_digits(self):
        self.assertEqual(hashlib.md5(b"123456789").hexdigest(), "25f9e794323b453885f5181f1b624d0b")

class TestMd5Update(unittest.TestCase):
    def test_md5_update_single(self):
        h = hashlib.md5()
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_md5_update_multiple(self):
        h = hashlib.md5()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(h.hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_md5_update_empty(self):
        h = hashlib.md5()
        h.update(b"")
        self.assertEqual(h.hexdigest(), "d41d8cd98f00b204e9800998ecf8427e")

    def test_md5_update_bytes(self):
        h = hashlib.md5()
        h.update(b"\x00\x01\x02")
        self.assertEqual(len(h.hexdigest()), 32)

class TestSha1Basic(unittest.TestCase):
    def test_sha1_hello(self):
        self.assertEqual(hashlib.sha1(b"hello").hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_sha1_empty(self):
        self.assertEqual(hashlib.sha1(b"").hexdigest(), "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    def test_sha1_world(self):
        self.assertEqual(hashlib.sha1(b"world").hexdigest(), "7c211433f02071597741e6ff5a8ea34789abbf43")

    def test_sha1_abc(self):
        self.assertEqual(hashlib.sha1(b"abc").hexdigest(), "a9993e364706816aba3e25717850c26c9cd0d89d")

    def test_sha1_digits(self):
        self.assertEqual(hashlib.sha1(b"123456789").hexdigest(), "f7c3bc1d808e04732adf679965ccc34ca7ae3441")

class TestSha1Update(unittest.TestCase):
    def test_sha1_update_single(self):
        h = hashlib.sha1()
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_sha1_update_multiple(self):
        h = hashlib.sha1()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(h.hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

class TestSha256Basic(unittest.TestCase):
    def test_sha256_hello(self):
        self.assertEqual(hashlib.sha256(b"hello").hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_sha256_empty(self):
        self.assertEqual(hashlib.sha256(b"").hexdigest(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    def test_sha256_world(self):
        self.assertEqual(hashlib.sha256(b"world").hexdigest(), "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7")

    def test_sha256_abc(self):
        self.assertEqual(hashlib.sha256(b"abc").hexdigest(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    def test_sha256_digits(self):
        self.assertEqual(hashlib.sha256(b"123456789").hexdigest(), "15e2b0d3c33891ebb0f1ef609ec419420c20e320ce94c65fbc8c3312448eb225")

class TestSha256Update(unittest.TestCase):
    def test_sha256_update_single(self):
        h = hashlib.sha256()
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_sha256_update_multiple(self):
        h = hashlib.sha256()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(h.hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

class TestSha512Basic(unittest.TestCase):
    def test_sha512_hello(self):
        result = hashlib.sha512(b"hello").hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_empty(self):
        result = hashlib.sha512(b"").hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_world(self):
        result = hashlib.sha512(b"world").hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_abc(self):
        result = hashlib.sha512(b"abc").hexdigest()
        self.assertEqual(len(result), 128)

class TestSha512Update(unittest.TestCase):
    def test_sha512_update_single(self):
        h = hashlib.sha512()
        h.update(b"hello")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_update_multiple(self):
        h = hashlib.sha512()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(len(h.hexdigest()), 128)

class TestDigestLength(unittest.TestCase):
    def test_md5_length(self):
        result = hashlib.md5(b"test").hexdigest()
        self.assertEqual(len(result), 32)

    def test_sha1_length(self):
        result = hashlib.sha1(b"test").hexdigest()
        self.assertEqual(len(result), 40)

    def test_sha256_length(self):
        result = hashlib.sha256(b"test").hexdigest()
        self.assertEqual(len(result), 64)

    def test_sha512_length(self):
        result = hashlib.sha512(b"test").hexdigest()
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

class TestDifferentInputs(unittest.TestCase):
    def test_md5_different(self):
        a = hashlib.md5(b"hello").hexdigest()
        b = hashlib.md5(b"world").hexdigest()
        self.assertNotEqual(a, b)

    def test_sha1_different(self):
        a = hashlib.sha1(b"hello").hexdigest()
        b = hashlib.sha1(b"world").hexdigest()
        self.assertNotEqual(a, b)

    def test_sha256_different(self):
        a = hashlib.sha256(b"hello").hexdigest()
        b = hashlib.sha256(b"world").hexdigest()
        self.assertNotEqual(a, b)

    def test_sha512_different(self):
        a = hashlib.sha512(b"hello").hexdigest()
        b = hashlib.sha512(b"world").hexdigest()
        self.assertNotEqual(a, b)

if __name__ == "__main__":
    unittest.main()
