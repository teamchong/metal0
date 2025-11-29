"""Extended hashlib module tests for metal0 C interop - sha224, sha384"""
import hashlib
import unittest

class TestSha224Basic(unittest.TestCase):
    def test_sha224_hello(self):
        result = hashlib.sha224(b"hello").hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha224_empty(self):
        result = hashlib.sha224(b"").hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha224_world(self):
        result = hashlib.sha224(b"world").hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha224_abc(self):
        result = hashlib.sha224(b"abc").hexdigest()
        self.assertEqual(len(result), 56)

    def test_sha224_digits(self):
        result = hashlib.sha224(b"123456789").hexdigest()
        self.assertEqual(len(result), 56)

class TestSha224Update(unittest.TestCase):
    def test_sha224_update_single(self):
        h = hashlib.sha224()
        h.update(b"hello")
        self.assertEqual(len(h.hexdigest()), 56)

    def test_sha224_update_multiple(self):
        h = hashlib.sha224()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(len(h.hexdigest()), 56)

class TestSha384Basic(unittest.TestCase):
    def test_sha384_hello(self):
        result = hashlib.sha384(b"hello").hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha384_empty(self):
        result = hashlib.sha384(b"").hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha384_world(self):
        result = hashlib.sha384(b"world").hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha384_abc(self):
        result = hashlib.sha384(b"abc").hexdigest()
        self.assertEqual(len(result), 96)

    def test_sha384_digits(self):
        result = hashlib.sha384(b"123456789").hexdigest()
        self.assertEqual(len(result), 96)

class TestSha384Update(unittest.TestCase):
    def test_sha384_update_single(self):
        h = hashlib.sha384()
        h.update(b"hello")
        self.assertEqual(len(h.hexdigest()), 96)

    def test_sha384_update_multiple(self):
        h = hashlib.sha384()
        h.update(b"hel")
        h.update(b"lo")
        self.assertEqual(len(h.hexdigest()), 96)

class TestHashNew(unittest.TestCase):
    def test_new_md5(self):
        h = hashlib.new("md5")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "5d41402abc4b2a76b9719d911017c592")

    def test_new_sha1(self):
        h = hashlib.new("sha1")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

    def test_new_sha256(self):
        h = hashlib.new("sha256")
        h.update(b"hello")
        self.assertEqual(h.hexdigest(), "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

    def test_new_sha512(self):
        h = hashlib.new("sha512")
        h.update(b"hello")
        self.assertEqual(len(h.hexdigest()), 128)

class TestMultipleUpdates(unittest.TestCase):
    def test_md5_three_updates(self):
        h = hashlib.md5()
        h.update(b"hel")
        h.update(b"lo ")
        h.update(b"world")
        result = h.hexdigest()
        self.assertEqual(len(result), 32)

    def test_sha256_three_updates(self):
        h = hashlib.sha256()
        h.update(b"hel")
        h.update(b"lo ")
        h.update(b"world")
        result = h.hexdigest()
        self.assertEqual(len(result), 64)

    def test_sha512_three_updates(self):
        h = hashlib.sha512()
        h.update(b"hel")
        h.update(b"lo ")
        h.update(b"world")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

class TestLongData(unittest.TestCase):
    def test_md5_long(self):
        data = b"a" * 10000
        result = hashlib.md5(data).hexdigest()
        self.assertEqual(len(result), 32)

    def test_sha1_long(self):
        data = b"a" * 10000
        result = hashlib.sha1(data).hexdigest()
        self.assertEqual(len(result), 40)

    def test_sha256_long(self):
        data = b"a" * 10000
        result = hashlib.sha256(data).hexdigest()
        self.assertEqual(len(result), 64)

    def test_sha512_long(self):
        data = b"a" * 10000
        result = hashlib.sha512(data).hexdigest()
        self.assertEqual(len(result), 128)

if __name__ == "__main__":
    unittest.main()
