"""Hashlib tests with longer data for metal0 C interop"""
import hashlib
import unittest

class TestMd5Long(unittest.TestCase):
    def test_md5_sentence(self):
        h = hashlib.md5(b"The quick brown fox jumps over the lazy dog")
        result = h.hexdigest()
        self.assertEqual(result, "9e107d9d372bb6826bd81d3542a419d6")

    def test_md5_numbers(self):
        h = hashlib.md5(b"1234567890")
        result = h.hexdigest()
        self.assertEqual(result, "e807f1fcf82d132f9bb018ca6738a19f")

    def test_md5_repeated(self):
        h = hashlib.md5(b"aaaaaaaaaa")
        result = h.hexdigest()
        self.assertEqual(result, "e09c80c42fda55f9d992e59ca6b3307d")

class TestSha1Long(unittest.TestCase):
    def test_sha1_sentence(self):
        h = hashlib.sha1(b"The quick brown fox jumps over the lazy dog")
        result = h.hexdigest()
        self.assertEqual(result, "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")

    def test_sha1_numbers(self):
        h = hashlib.sha1(b"1234567890")
        result = h.hexdigest()
        self.assertEqual(result, "01b307acba4f54f55aafc33bb06bbbf6ca803e9a")

    def test_sha1_repeated(self):
        h = hashlib.sha1(b"aaaaaaaaaa")
        result = h.hexdigest()
        self.assertEqual(result, "3495ff69d34671d1e15b33a63c1379fdedd3a32a")

class TestSha256Long(unittest.TestCase):
    def test_sha256_sentence(self):
        h = hashlib.sha256(b"The quick brown fox jumps over the lazy dog")
        result = h.hexdigest()
        self.assertEqual(result, "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

    def test_sha256_numbers(self):
        h = hashlib.sha256(b"1234567890")
        result = h.hexdigest()
        self.assertEqual(result, "c775e7b757ede630cd0aa1113bd102661ab38829ca52a6422ab782862f268646")

    def test_sha256_repeated(self):
        h = hashlib.sha256(b"aaaaaaaaaa")
        result = h.hexdigest()
        self.assertEqual(result, "bf2cb58a68f684d95a3b78ef8f661c9a4e5b09e82cc8f9cc88cce90528caeb27")

class TestSha512Long(unittest.TestCase):
    def test_sha512_sentence_len(self):
        h = hashlib.sha512(b"The quick brown fox jumps over the lazy dog")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

    def test_sha512_numbers_len(self):
        h = hashlib.sha512(b"1234567890")
        result = h.hexdigest()
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

if __name__ == "__main__":
    unittest.main()
