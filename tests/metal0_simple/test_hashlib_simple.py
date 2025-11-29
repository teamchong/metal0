"""Comprehensive hashlib module tests for metal0"""
import hashlib
import unittest

class TestMd5(unittest.TestCase):
    def test_md5_empty(self):
        h = hashlib.md5()
        h.update(b'')
        result = h.hexdigest()
        self.assertEqual(result, 'd41d8cd98f00b204e9800998ecf8427e')

    def test_md5_hello(self):
        h = hashlib.md5()
        h.update(b'hello')
        result = h.hexdigest()
        self.assertEqual(result, '5d41402abc4b2a76b9719d911017c592')

    def test_md5_world(self):
        h = hashlib.md5()
        h.update(b'world')
        result = h.hexdigest()
        self.assertEqual(result, '7d793037a0760186574b0282f2f435e7')

    def test_md5_multiple_updates(self):
        h = hashlib.md5()
        h.update(b'hello')
        h.update(b'world')
        result = h.hexdigest()
        self.assertEqual(result, 'fc5e038d38a57032085441e7fe7010b0')

    def test_md5_test(self):
        h = hashlib.md5()
        h.update(b'test')
        result = h.hexdigest()
        self.assertEqual(result, '098f6bcd4621d373cade4e832627b4f6')

    def test_md5_abc(self):
        h = hashlib.md5()
        h.update(b'abc')
        result = h.hexdigest()
        self.assertEqual(result, '900150983cd24fb0d6963f7d28e17f72')

class TestSha1(unittest.TestCase):
    def test_sha1_empty(self):
        h = hashlib.sha1()
        h.update(b'')
        result = h.hexdigest()
        self.assertEqual(result, 'da39a3ee5e6b4b0d3255bfef95601890afd80709')

    def test_sha1_hello(self):
        h = hashlib.sha1()
        h.update(b'hello')
        result = h.hexdigest()
        self.assertEqual(result, 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d')

    def test_sha1_test(self):
        h = hashlib.sha1()
        h.update(b'test')
        result = h.hexdigest()
        self.assertEqual(result, 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3')

    def test_sha1_abc(self):
        h = hashlib.sha1()
        h.update(b'abc')
        result = h.hexdigest()
        self.assertEqual(result, 'a9993e364706816aba3e25717850c26c9cd0d89d')

class TestSha256(unittest.TestCase):
    def test_sha256_empty(self):
        h = hashlib.sha256()
        h.update(b'')
        result = h.hexdigest()
        self.assertEqual(result, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')

    def test_sha256_hello(self):
        h = hashlib.sha256()
        h.update(b'hello')
        result = h.hexdigest()
        self.assertEqual(result, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824')

    def test_sha256_test(self):
        h = hashlib.sha256()
        h.update(b'test')
        result = h.hexdigest()
        self.assertEqual(result, '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08')

    def test_sha256_abc(self):
        h = hashlib.sha256()
        h.update(b'abc')
        result = h.hexdigest()
        self.assertEqual(result, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

class TestSha512(unittest.TestCase):
    def test_sha512_empty(self):
        h = hashlib.sha512()
        h.update(b'')
        result = h.hexdigest()
        expected = 'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e'
        self.assertEqual(result, expected)

    def test_sha512_hello(self):
        h = hashlib.sha512()
        h.update(b'hello')
        result = h.hexdigest()
        expected = '9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043'
        self.assertEqual(result, expected)

    def test_sha512_test(self):
        h = hashlib.sha512()
        h.update(b'test')
        result = h.hexdigest()
        expected = 'ee26b0dd4af7e749aa1a8ee3c10ae9923f618980772e473f8819a5d4940e0db27ac185f8a0e1d5f84f88bc887fd67b143732c304cc5fa9ad8e6f57f50028a8ff'
        self.assertEqual(result, expected)

class TestHashlibNew(unittest.TestCase):
    def test_new_md5(self):
        h = hashlib.new('md5')
        h.update(b'test')
        self.assertEqual(len(h.hexdigest()), 32)

    def test_new_sha1(self):
        h = hashlib.new('sha1')
        h.update(b'test')
        self.assertEqual(len(h.hexdigest()), 40)

    def test_new_sha256(self):
        h = hashlib.new('sha256')
        h.update(b'test')
        self.assertEqual(len(h.hexdigest()), 64)

if __name__ == "__main__":
    unittest.main()
