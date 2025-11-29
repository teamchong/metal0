"""Hashlib digest() binary output tests for metal0 C interop"""
import hashlib
import unittest

class TestMd5Digest(unittest.TestCase):
    def test_md5_digest_length(self):
        result = hashlib.md5(b"hello").digest()
        self.assertEqual(len(result), 16)

    def test_md5_digest_empty(self):
        result = hashlib.md5(b"").digest()
        self.assertEqual(len(result), 16)

    def test_md5_digest_binary(self):
        result = hashlib.md5(b"test").digest()
        self.assertEqual(len(result), 16)

class TestSha1Digest(unittest.TestCase):
    def test_sha1_digest_length(self):
        result = hashlib.sha1(b"hello").digest()
        self.assertEqual(len(result), 20)

    def test_sha1_digest_empty(self):
        result = hashlib.sha1(b"").digest()
        self.assertEqual(len(result), 20)

    def test_sha1_digest_binary(self):
        result = hashlib.sha1(b"test").digest()
        self.assertEqual(len(result), 20)

class TestSha256Digest(unittest.TestCase):
    def test_sha256_digest_length(self):
        result = hashlib.sha256(b"hello").digest()
        self.assertEqual(len(result), 32)

    def test_sha256_digest_empty(self):
        result = hashlib.sha256(b"").digest()
        self.assertEqual(len(result), 32)

    def test_sha256_digest_binary(self):
        result = hashlib.sha256(b"test").digest()
        self.assertEqual(len(result), 32)

class TestSha512Digest(unittest.TestCase):
    def test_sha512_digest_length(self):
        result = hashlib.sha512(b"hello").digest()
        self.assertEqual(len(result), 64)

    def test_sha512_digest_empty(self):
        result = hashlib.sha512(b"").digest()
        self.assertEqual(len(result), 64)

    def test_sha512_digest_binary(self):
        result = hashlib.sha512(b"test").digest()
        self.assertEqual(len(result), 64)

class TestDigestUpdate(unittest.TestCase):
    def test_md5_update_digest(self):
        h = hashlib.md5()
        h.update(b"hello")
        result = h.digest()
        self.assertEqual(len(result), 16)

    def test_sha256_update_digest(self):
        h = hashlib.sha256()
        h.update(b"hello")
        result = h.digest()
        self.assertEqual(len(result), 32)

    def test_sha512_update_digest(self):
        h = hashlib.sha512()
        h.update(b"hello")
        result = h.digest()
        self.assertEqual(len(result), 64)

class TestDigestConsistency(unittest.TestCase):
    def test_md5_digest_consistent(self):
        a = hashlib.md5(b"test").digest()
        b = hashlib.md5(b"test").digest()
        self.assertEqual(a, b)

    def test_sha256_digest_consistent(self):
        a = hashlib.sha256(b"test").digest()
        b = hashlib.sha256(b"test").digest()
        self.assertEqual(a, b)

    def test_sha512_digest_consistent(self):
        a = hashlib.sha512(b"test").digest()
        b = hashlib.sha512(b"test").digest()
        self.assertEqual(a, b)

class TestDigestHexdigestRelation(unittest.TestCase):
    def test_md5_digest_hexdigest_length(self):
        h = hashlib.md5(b"hello")
        digest_len = len(h.digest())
        hexdigest_len = len(h.hexdigest())
        self.assertEqual(hexdigest_len, digest_len * 2)

    def test_sha256_digest_hexdigest_length(self):
        h = hashlib.sha256(b"hello")
        digest_len = len(h.digest())
        hexdigest_len = len(h.hexdigest())
        self.assertEqual(hexdigest_len, digest_len * 2)

if __name__ == "__main__":
    unittest.main()
