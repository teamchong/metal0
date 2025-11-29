"""Hashlib MD5 C interop tests"""
import hashlib
import unittest

class TestMd5Basic(unittest.TestCase):
    def test_md5_empty(self):
        h = hashlib.md5(b"")
        self.assertEqual(h.hexdigest(), "d41d8cd98f00b204e9800998ecf8427e")

    def test_md5_a(self):
        h = hashlib.md5(b"a")
        self.assertEqual(h.hexdigest(), "0cc175b9c0f1b6a831c399e269772661")

    def test_md5_abc(self):
        h = hashlib.md5(b"abc")
        self.assertEqual(h.hexdigest(), "900150983cd24fb0d6963f7d28e17f72")

    def test_md5_hello(self):
        h = hashlib.md5(b"hello")
        self.assertEqual(h.hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_md5_world(self):
        h = hashlib.md5(b"world")
        self.assertEqual(h.hexdigest(), "7d793037a0760186574b0282f2f435e7")

class TestMd5Longer(unittest.TestCase):
    def test_md5_sentence(self):
        h = hashlib.md5(b"The quick brown fox jumps over the lazy dog")
        self.assertEqual(h.hexdigest(), "9e107d9d372bb6826bd81d3542a419d6")

    def test_md5_numbers(self):
        h = hashlib.md5(b"1234567890")
        self.assertEqual(h.hexdigest(), "e807f1fcf82d132f9bb018ca6738a19f")

    def test_md5_repeated(self):
        h = hashlib.md5(b"aaaaaaaaaa")
        self.assertEqual(h.hexdigest(), "e09c80c42fda55f9d992e59ca6b3307d")

class TestMd5Consistency(unittest.TestCase):
    def test_md5_consistent_1(self):
        a = hashlib.md5(b"test").hexdigest()
        b = hashlib.md5(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_md5_consistent_2(self):
        a = hashlib.md5(b"hello world").hexdigest()
        b = hashlib.md5(b"hello world").hexdigest()
        self.assertEqual(a, b)

class TestMd5DigestSize(unittest.TestCase):
    def test_md5_hexdigest_length(self):
        h = hashlib.md5(b"test")
        self.assertEqual(len(h.hexdigest()), 32)

    def test_md5_returns_string(self):
        h = hashlib.md5(b"test")
        self.assertIsInstance(h.hexdigest(), str)

if __name__ == "__main__":
    unittest.main()
