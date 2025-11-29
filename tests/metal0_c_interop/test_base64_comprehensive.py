"""Comprehensive base64 module tests for metal0 C interop"""
import base64
import unittest

class TestB64EncodeBasic(unittest.TestCase):
    def test_encode_hello(self):
        result = base64.b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

    def test_encode_world(self):
        result = base64.b64encode(b"world")
        self.assertEqual(result, b"d29ybGQ=")

    def test_encode_empty(self):
        result = base64.b64encode(b"")
        self.assertEqual(result, b"")

    def test_encode_abc(self):
        result = base64.b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_encode_test(self):
        result = base64.b64encode(b"test")
        self.assertEqual(result, b"dGVzdA==")

class TestB64EncodeMore(unittest.TestCase):
    def test_encode_space(self):
        result = base64.b64encode(b" ")
        self.assertEqual(result, b"IA==")

    def test_encode_digits(self):
        result = base64.b64encode(b"123")
        self.assertEqual(result, b"MTIz")

    def test_encode_sentence(self):
        result = base64.b64encode(b"Hello World")
        self.assertEqual(result, b"SGVsbG8gV29ybGQ=")

    def test_encode_punctuation(self):
        result = base64.b64encode(b"!@#")
        self.assertEqual(result, b"IUAj")

class TestB64DecodeBasic(unittest.TestCase):
    def test_decode_hello(self):
        result = base64.b64decode(b"aGVsbG8=")
        self.assertEqual(result, b"hello")

    def test_decode_world(self):
        result = base64.b64decode(b"d29ybGQ=")
        self.assertEqual(result, b"world")

    def test_decode_empty(self):
        result = base64.b64decode(b"")
        self.assertEqual(result, b"")

    def test_decode_abc(self):
        result = base64.b64decode(b"YWJj")
        self.assertEqual(result, b"abc")

    def test_decode_test(self):
        result = base64.b64decode(b"dGVzdA==")
        self.assertEqual(result, b"test")

class TestB64DecodeMore(unittest.TestCase):
    def test_decode_space(self):
        result = base64.b64decode(b"IA==")
        self.assertEqual(result, b" ")

    def test_decode_digits(self):
        result = base64.b64decode(b"MTIz")
        self.assertEqual(result, b"123")

    def test_decode_sentence(self):
        result = base64.b64decode(b"SGVsbG8gV29ybGQ=")
        self.assertEqual(result, b"Hello World")

class TestB64Roundtrip(unittest.TestCase):
    def test_roundtrip_hello(self):
        encoded = base64.b64encode(b"hello")
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, b"hello")

    def test_roundtrip_world(self):
        encoded = base64.b64encode(b"world")
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, b"world")

    def test_roundtrip_sentence(self):
        encoded = base64.b64encode(b"The quick brown fox")
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, b"The quick brown fox")

    def test_roundtrip_numbers(self):
        encoded = base64.b64encode(b"1234567890")
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, b"1234567890")

class TestUrlsafeEncode(unittest.TestCase):
    def test_urlsafe_encode_hello(self):
        result = base64.urlsafe_b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

    def test_urlsafe_encode_world(self):
        result = base64.urlsafe_b64encode(b"world")
        self.assertEqual(result, b"d29ybGQ=")

    def test_urlsafe_encode_empty(self):
        result = base64.urlsafe_b64encode(b"")
        self.assertEqual(result, b"")

class TestUrlsafeDecode(unittest.TestCase):
    def test_urlsafe_decode_hello(self):
        result = base64.urlsafe_b64decode(b"aGVsbG8=")
        self.assertEqual(result, b"hello")

    def test_urlsafe_decode_world(self):
        result = base64.urlsafe_b64decode(b"d29ybGQ=")
        self.assertEqual(result, b"world")

    def test_urlsafe_decode_empty(self):
        result = base64.urlsafe_b64decode(b"")
        self.assertEqual(result, b"")

class TestConsistency(unittest.TestCase):
    def test_encode_consistent(self):
        a = base64.b64encode(b"test")
        b = base64.b64encode(b"test")
        self.assertEqual(a, b)

    def test_decode_consistent(self):
        a = base64.b64decode(b"dGVzdA==")
        b = base64.b64decode(b"dGVzdA==")
        self.assertEqual(a, b)

if __name__ == "__main__":
    unittest.main()
