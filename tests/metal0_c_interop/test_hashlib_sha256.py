"""Hashlib SHA256 C interop tests"""
import hashlib
import unittest

class TestSha256Basic(unittest.TestCase):
    def test_sha256_empty(self):
        h = hashlib.sha256(b"")
        self.assertEqual(h.hexdigest(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    def test_sha256_a(self):
        h = hashlib.sha256(b"a")
        self.assertEqual(h.hexdigest(), "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")

    def test_sha256_abc(self):
        h = hashlib.sha256(b"abc")
        self.assertEqual(h.hexdigest(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    def test_sha256_hello(self):
        h = hashlib.sha256(b"hello")
        self.assertEqual(h.hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_sha256_world(self):
        h = hashlib.sha256(b"world")
        self.assertEqual(h.hexdigest(), "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7")

class TestSha256Longer(unittest.TestCase):
    def test_sha256_sentence(self):
        h = hashlib.sha256(b"The quick brown fox jumps over the lazy dog")
        self.assertEqual(h.hexdigest(), "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

    def test_sha256_numbers(self):
        h = hashlib.sha256(b"1234567890")
        self.assertEqual(h.hexdigest(), "c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646")

    def test_sha256_repeated(self):
        h = hashlib.sha256(b"aaaaaaaaaa")
        self.assertEqual(h.hexdigest(), "bf2cb58a68f684d95a3b78ef8f661c9a4e5b09e82cc8f9cc88cce90528caeb27")

class TestSha256Consistency(unittest.TestCase):
    def test_sha256_consistent_1(self):
        a = hashlib.sha256(b"test").hexdigest()
        b = hashlib.sha256(b"test").hexdigest()
        self.assertEqual(a, b)

    def test_sha256_consistent_2(self):
        a = hashlib.sha256(b"hello world").hexdigest()
        b = hashlib.sha256(b"hello world").hexdigest()
        self.assertEqual(a, b)

class TestSha256DigestSize(unittest.TestCase):
    def test_sha256_hexdigest_length(self):
        h = hashlib.sha256(b"test")
        self.assertEqual(len(h.hexdigest()), 64)

    def test_sha256_returns_string(self):
        h = hashlib.sha256(b"test")
        self.assertIsInstance(h.hexdigest(), str)

if __name__ == "__main__":
    unittest.main()
