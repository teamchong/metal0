"""Hashlib SHA1 C interop tests"""
import hashlib
import unittest

class TestSha1Basic(unittest.TestCase):
    def test_sha1_empty(self):
        h = hashlib.sha1(b"")
        self.assertEqual(h.hexdigest(), "da39a3ee5e6b4b0d3255bfef95601890afd80709")

    def test_sha1_a(self):
        h = hashlib.sha1(b"a")
        self.assertEqual(h.hexdigest(), "86f7e437faa5a7fce15d1ddcb9eaeaea377667b8")

    def test_sha1_abc(self):
        h = hashlib.sha1(b"abc")
        self.assertEqual(h.hexdigest(), "a9993e364706816aba3e25717850c26c9cd0d89d")

    def test_sha1_hello(self):
        h = hashlib.sha1(b"hello")
        self.assertEqual(h.hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_sha1_world(self):
        h = hashlib.sha1(b"world")
        self.assertEqual(h.hexdigest(), "7c211433f02071597741e6ff5a8ea34789abbf43")

class TestSha1Longer(unittest.TestCase):
    def test_sha1_sentence(self):
        h = hashlib.sha1(b"The quick brown fox jumps over the lazy dog")
        self.assertEqual(h.hexdigest(), "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")

    def test_sha1_numbers(self):
        h = hashlib.sha1(b"1234567890")
        self.assertEqual(h.hexdigest(), "01b307acba4f54f55aafc33bb06bbbf6ca803e9a")

    def test_sha1_repeated(self):
        h = hashlib.sha1(b"aaaaaaaaaa")
        self.assertEqual(h.hexdigest(), "3495ff69d34671d1e15b33a63c1379fdedd3a32a")

class TestSha1Consistency(unittest.TestCase):
    def test_sha1_consistent_1(self):
        a = hashlib.sha1(b"test").hexdigest()
        b = hashlib.sha1(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha1_consistent_2(self):
        a = hashlib.sha1(b"hello world").hexdigest()
        b = hashlib.sha1(b"hello world").hexdigest()
        self.assertEqual(a, b)

class TestSha1DigestSize(unittest.TestCase):
    def test_sha1_hexdigest_length(self):
        h = hashlib.sha1(b"test")
        self.assertEqual(len(h.hexdigest()), 40)

    def test_sha1_returns_string(self):
        h = hashlib.sha1(b"test")
        self.assertIsInstance(h.hexdigest(), str)

if __name__ == "__main__":
    unittest.main()
