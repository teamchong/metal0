"""Hashlib sha224 and sha384 tests for metal0 C interop"""
import hashlib
import unittest

class TestSha224Basic(unittest.TestCase):
    def test_sha224_hello(self):
        h = hashlib.sha224(b"hello")
        result = h.hexdigest()
        self.assertEqual(result, "ea09ae9cc6768c50fcee903ed054556e5bfc8347907f12598aa24193")

    def test_sha224_world(self):
        h = hashlib.sha224(b"world")
        result = h.hexdigest()
        self.assertEqual(result, "06d2dbdb71973e31e4f1df3d7001fa7de268aa72fcb1f6f9ea37e0e5")

    def test_sha224_empty(self):
        h = hashlib.sha224(b"")
        result = h.hexdigest()
        self.assertEqual(result, "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f")

    def test_sha224_abc(self):
        h = hashlib.sha224(b"abc")
        result = h.hexdigest()
        self.assertEqual(result, "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7")

    def test_sha224_length(self):
        h = hashlib.sha224(b"test")
        result = h.hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha224_test(self):
        h = hashlib.sha224(b"test")
        result = h.hexdigest()
        self.assertEqual(result, "90a3ed9e32b2aaf4c61c410eb925426119e1a9dc53d4286ade99a809")

    def test_sha224_python(self):
        h = hashlib.sha224(b"python")
        result = h.hexdigest()
        self.assertEqual(result, "dace1c32d56e6f2bd077266a5a381fcf7ff9052e0a269e32cd52a551")

class TestSha384Basic(unittest.TestCase):
    def test_sha384_hello(self):
        h = hashlib.sha384(b"hello")
        result = h.hexdigest()
        self.assertEqual(result, "59e1748777448c69de6b800d7a33bbfb9ff1b463e44354c3553bcdb9c666fa90125a3c79f90397bdf5f6a13de828684f")

    def test_sha384_world(self):
        h = hashlib.sha384(b"world")
        result = h.hexdigest()
        self.assertEqual(result, "a4d102bb2a39b6f1d9e481ef1a16b8948a0df2b594fd031bad6f201fbd6b0656846a6e58a30aa57ff34d912e7d3ea185")

    def test_sha384_empty(self):
        h = hashlib.sha384(b"")
        result = h.hexdigest()
        self.assertEqual(result, "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b")

    def test_sha384_abc(self):
        h = hashlib.sha384(b"abc")
        result = h.hexdigest()
        self.assertEqual(result, "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")

    def test_sha384_length(self):
        h = hashlib.sha384(b"test")
        result = h.hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha384_test(self):
        h = hashlib.sha384(b"test")
        result = h.hexdigest()
        self.assertEqual(result, "768412320f7b0aa5812fce428dc4706b3cae50e02a64caa16a782249bfe8efc4b7ef1ccb126255d196047dfedf17a0a9")

    def test_sha384_python(self):
        h = hashlib.sha384(b"python")
        result = h.hexdigest()
        self.assertEqual(result, "2690f7fce3051903a4e8b9f1f9ea705f070f03f9d84c353f2653cece80ea68130ef8defd53ef29af5f236e6cac7c7efb")

class TestSha224Digest(unittest.TestCase):
    def test_sha224_digest_length(self):
        h = hashlib.sha224(b"test")
        d = h.digest()
        self.assertEqual(len(d), 28)

    def test_sha224_digest_empty(self):
        h = hashlib.sha224(b"")
        d = h.digest()
        self.assertEqual(len(d), 28)

class TestSha384Digest(unittest.TestCase):
    def test_sha384_digest_length(self):
        h = hashlib.sha384(b"test")
        d = h.digest()
        self.assertEqual(len(d), 48)

    def test_sha384_digest_empty(self):
        h = hashlib.sha384(b"")
        d = h.digest()
        self.assertEqual(len(d), 48)

if __name__ == "__main__":
    unittest.main()
