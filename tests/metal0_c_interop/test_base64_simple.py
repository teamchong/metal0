"""Comprehensive base64 module tests for metal0"""
import base64
import unittest

class TestBase64Encode(unittest.TestCase):
    def test_b64encode_empty(self):
        result = base64.b64encode(b"")
        self.assertEqual(result, b"")

    def test_b64encode_hello(self):
        result = base64.b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

    def test_b64encode_world(self):
        result = base64.b64encode(b"world")
        self.assertEqual(result, b"d29ybGQ=")

    def test_b64encode_test(self):
        result = base64.b64encode(b"test")
        self.assertEqual(result, b"dGVzdA==")

class TestBase64Decode(unittest.TestCase):
    def test_b64decode_empty(self):
        result = base64.b64decode(b"")
        self.assertEqual(result, b"")

    def test_b64decode_hello(self):
        result = base64.b64decode(b"aGVsbG8=")
        self.assertEqual(result, b"hello")

    def test_b64decode_world(self):
        result = base64.b64decode(b"d29ybGQ=")
        self.assertEqual(result, b"world")

    def test_b64decode_test(self):
        result = base64.b64decode(b"dGVzdA==")
        self.assertEqual(result, b"test")

class TestUrlsafeEncode(unittest.TestCase):
    def test_urlsafe_encode_hello(self):
        result = base64.urlsafe_b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

    def test_urlsafe_encode_test(self):
        result = base64.urlsafe_b64encode(b"test")
        self.assertEqual(result, b"dGVzdA==")

class TestUrlsafeDecode(unittest.TestCase):
    def test_urlsafe_decode_hello(self):
        result = base64.urlsafe_b64decode(b"aGVsbG8=")
        self.assertEqual(result, b"hello")

    def test_urlsafe_decode_test(self):
        result = base64.urlsafe_b64decode(b"dGVzdA==")
        self.assertEqual(result, b"test")

class TestStandardEncode(unittest.TestCase):
    def test_standard_encode_hello(self):
        result = base64.standard_b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

class TestStandardDecode(unittest.TestCase):
    def test_standard_decode_hello(self):
        result = base64.standard_b64decode(b"aGVsbG8=")
        self.assertEqual(result, b"hello")

class TestRoundtrip(unittest.TestCase):
    def test_roundtrip_hello(self):
        original = b"hello"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_binary(self):
        original = b"\x00\x01\x02\x03"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_longer(self):
        original = b"The quick brown fox"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_empty(self):
        original = b""
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_single_byte(self):
        original = b"X"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_two_bytes(self):
        original = b"XY"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

if __name__ == "__main__":
    unittest.main()
