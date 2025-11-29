"""Hashlib SHA512 C interop tests"""
import hashlib
import unittest

class TestSha512Basic(unittest.TestCase):
    def test_sha512_empty_len(self):
        h = hashlib.sha512(b"")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_a_len(self):
        h = hashlib.sha512(b"a")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_abc_len(self):
        h = hashlib.sha512(b"abc")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_hello_len(self):
        h = hashlib.sha512(b"hello")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_world_len(self):
        h = hashlib.sha512(b"world")
        self.assertEqual(len(h.hexdigest()), 128)

class TestSha512Longer(unittest.TestCase):
    def test_sha512_sentence_len(self):
        h = hashlib.sha512(b"The quick brown fox jumps over the lazy dog")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_numbers_len(self):
        h = hashlib.sha512(b"1234567890")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_repeated_len(self):
        h = hashlib.sha512(b"aaaaaaaaaa")
        self.assertEqual(len(h.hexdigest()), 128)

class TestSha512Consistency(unittest.TestCase):
    def test_sha512_consistent_1(self):
        a = hashlib.sha512(b"test").hexdigest()
        b = hashlib.sha512(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha512_consistent_2(self):
        a = hashlib.sha512(b"hello world").hexdigest()
        b = hashlib.sha512(b"hello world").hexdigest()
        self.assertEqual(a, b)

class TestSha512DigestSize(unittest.TestCase):
    def test_sha512_hexdigest_length(self):
        h = hashlib.sha512(b"test")
        self.assertEqual(len(h.hexdigest()), 128)

    def test_sha512_returns_string(self):
        h = hashlib.sha512(b"test")
        self.assertIsInstance(h.hexdigest(), str)

if __name__ == "__main__":
    unittest.main()
