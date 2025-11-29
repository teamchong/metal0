"""Base64 padding and edge case tests for metal0 C interop"""
import base64
import unittest

class TestB64Padding(unittest.TestCase):
    def test_encode_no_padding(self):
        result = base64.b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_encode_one_padding(self):
        result = base64.b64encode(b"ab")
        self.assertEqual(result, b"YWI=")

    def test_encode_two_padding(self):
        result = base64.b64encode(b"a")
        self.assertEqual(result, b"YQ==")

    def test_decode_no_padding(self):
        result = base64.b64decode(b"YWJj")
        self.assertEqual(result, b"abc")

    def test_decode_one_padding(self):
        result = base64.b64decode(b"YWI=")
        self.assertEqual(result, b"ab")

    def test_decode_two_padding(self):
        result = base64.b64decode(b"YQ==")
        self.assertEqual(result, b"a")

class TestB64Lengths(unittest.TestCase):
    def test_encode_4_chars(self):
        result = base64.b64encode(b"abcd")
        self.assertEqual(result, b"YWJjZA==")

    def test_encode_5_chars(self):
        result = base64.b64encode(b"abcde")
        self.assertEqual(result, b"YWJjZGU=")

    def test_encode_6_chars(self):
        result = base64.b64encode(b"abcdef")
        self.assertEqual(result, b"YWJjZGVm")

    def test_decode_4_chars(self):
        result = base64.b64decode(b"YWJjZA==")
        self.assertEqual(result, b"abcd")

    def test_decode_5_chars(self):
        result = base64.b64decode(b"YWJjZGU=")
        self.assertEqual(result, b"abcde")

    def test_decode_6_chars(self):
        result = base64.b64decode(b"YWJjZGVm")
        self.assertEqual(result, b"abcdef")

class TestB64Empty(unittest.TestCase):
    def test_encode_empty(self):
        result = base64.b64encode(b"")
        self.assertEqual(result, b"")

    def test_decode_empty(self):
        result = base64.b64decode(b"")
        self.assertEqual(result, b"")

    def test_urlsafe_encode_empty(self):
        result = base64.urlsafe_b64encode(b"")
        self.assertEqual(result, b"")

    def test_urlsafe_decode_empty(self):
        result = base64.urlsafe_b64decode(b"")
        self.assertEqual(result, b"")

class TestUrlsafeBasic(unittest.TestCase):
    def test_urlsafe_encode_abc(self):
        result = base64.urlsafe_b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_urlsafe_decode_abc(self):
        result = base64.urlsafe_b64decode(b"YWJj")
        self.assertEqual(result, b"abc")

    def test_urlsafe_encode_test(self):
        result = base64.urlsafe_b64encode(b"test")
        self.assertEqual(result, b"dGVzdA==")

    def test_urlsafe_decode_test(self):
        result = base64.urlsafe_b64decode(b"dGVzdA==")
        self.assertEqual(result, b"test")

if __name__ == "__main__":
    unittest.main()
