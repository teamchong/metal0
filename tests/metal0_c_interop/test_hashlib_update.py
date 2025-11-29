"""Hashlib update() method tests for metal0 C interop"""
import hashlib
import unittest

class TestMd5Update(unittest.TestCase):
    def test_md5_update_two(self):
        h = hashlib.md5()
        h.update(b"hello")
        h.update(b"world")
        result = h.hexdigest()
        expected = hashlib.md5(b"helloworld").hexdigest()
        self.assertEqual(result, expected)

    def test_md5_update_three(self):
        h = hashlib.md5()
        h.update(b"a")
        h.update(b"b")
        h.update(b"c")
        result = h.hexdigest()
        expected = hashlib.md5(b"abc").hexdigest()
        self.assertEqual(result, expected)

    def test_md5_update_empty(self):
        h = hashlib.md5()
        h.update(b"")
        h.update(b"test")
        result = h.hexdigest()
        expected = hashlib.md5(b"test").hexdigest()
        self.assertEqual(result, expected)

    def test_md5_update_empty_twice(self):
        h = hashlib.md5()
        h.update(b"")
        h.update(b"")
        h.update(b"test")
        result = h.hexdigest()
        expected = hashlib.md5(b"test").hexdigest()
        self.assertEqual(result, expected)

class TestSha1Update(unittest.TestCase):
    def test_sha1_update_two(self):
        h = hashlib.sha1()
        h.update(b"hello")
        h.update(b"world")
        result = h.hexdigest()
        expected = hashlib.sha1(b"helloworld").hexdigest()
        self.assertEqual(result, expected)

    def test_sha1_update_three(self):
        h = hashlib.sha1()
        h.update(b"a")
        h.update(b"b")
        h.update(b"c")
        result = h.hexdigest()
        expected = hashlib.sha1(b"abc").hexdigest()
        self.assertEqual(result, expected)

class TestSha256Update(unittest.TestCase):
    def test_sha256_update_two(self):
        h = hashlib.sha256()
        h.update(b"hello")
        h.update(b"world")
        result = h.hexdigest()
        expected = hashlib.sha256(b"helloworld").hexdigest()
        self.assertEqual(result, expected)

    def test_sha256_update_three(self):
        h = hashlib.sha256()
        h.update(b"a")
        h.update(b"b")
        h.update(b"c")
        result = h.hexdigest()
        expected = hashlib.sha256(b"abc").hexdigest()
        self.assertEqual(result, expected)

class TestSha512Update(unittest.TestCase):
    def test_sha512_update_two(self):
        h = hashlib.sha512()
        h.update(b"hello")
        h.update(b"world")
        result = h.hexdigest()
        expected = hashlib.sha512(b"helloworld").hexdigest()
        self.assertEqual(result, expected)

    def test_sha512_update_length(self):
        h = hashlib.sha512()
        h.update(b"test")
        h.update(b"data")
        result = h.hexdigest()
        self.assertEqual(len(result), 128)

class TestUpdateBytes(unittest.TestCase):
    def test_md5_update_numbers(self):
        h = hashlib.md5()
        h.update(b"123")
        h.update(b"456")
        result = h.hexdigest()
        expected = hashlib.md5(b"123456").hexdigest()
        self.assertEqual(result, expected)

    def test_sha256_update_spaces(self):
        h = hashlib.sha256()
        h.update(b"hello ")
        h.update(b"world")
        result = h.hexdigest()
        expected = hashlib.sha256(b"hello world").hexdigest()
        self.assertEqual(result, expected)

if __name__ == "__main__":
    unittest.main()
