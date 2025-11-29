"""Base64 edge case tests for metal0 C interop"""
import base64
import unittest

class TestB64EncodeEdge(unittest.TestCase):
    def test_encode_single_char(self):
        result = base64.b64encode(b"a")
        self.assertEqual(result, b"YQ==")

    def test_encode_two_chars(self):
        result = base64.b64encode(b"ab")
        self.assertEqual(result, b"YWI=")

    def test_encode_three_chars(self):
        result = base64.b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_encode_four_chars(self):
        result = base64.b64encode(b"abcd")
        self.assertEqual(result, b"YWJjZA==")

    def test_encode_spaces(self):
        result = base64.b64encode(b"   ")
        self.assertEqual(result, b"ICAg")

    def test_encode_exclaim(self):
        result = base64.b64encode(b"!")
        self.assertEqual(result, b"IQ==")

    def test_encode_at(self):
        result = base64.b64encode(b"@")
        self.assertEqual(result, b"QA==")

class TestB64DecodeEdge(unittest.TestCase):
    def test_decode_single_char(self):
        result = base64.b64decode(b"YQ==")
        self.assertEqual(result, b"a")

    def test_decode_two_chars(self):
        result = base64.b64decode(b"YWI=")
        self.assertEqual(result, b"ab")

    def test_decode_three_chars(self):
        result = base64.b64decode(b"YWJj")
        self.assertEqual(result, b"abc")

    def test_decode_four_chars(self):
        result = base64.b64decode(b"YWJjZA==")
        self.assertEqual(result, b"abcd")

    def test_decode_spaces(self):
        result = base64.b64decode(b"ICAg")
        self.assertEqual(result, b"   ")

class TestUrlsafeEdge(unittest.TestCase):
    def test_urlsafe_encode_simple(self):
        result = base64.urlsafe_b64encode(b"test")
        self.assertEqual(result, b"dGVzdA==")

    def test_urlsafe_decode_simple(self):
        result = base64.urlsafe_b64decode(b"dGVzdA==")
        self.assertEqual(result, b"test")

    def test_urlsafe_encode_abc(self):
        result = base64.urlsafe_b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_urlsafe_decode_abc(self):
        result = base64.urlsafe_b64decode(b"YWJj")
        self.assertEqual(result, b"abc")

class TestB64Consistency(unittest.TestCase):
    def test_encode_same_input(self):
        a = base64.b64encode(b"hello")
        b = base64.b64encode(b"hello")
        self.assertEqual(a, b)

    def test_decode_same_input(self):
        a = base64.b64decode(b"aGVsbG8=")
        b = base64.b64decode(b"aGVsbG8=")
        self.assertEqual(a, b)

    def test_urlsafe_same_input(self):
        a = base64.urlsafe_b64encode(b"hello")
        b = base64.urlsafe_b64encode(b"hello")
        self.assertEqual(a, b)

if __name__ == "__main__":
    unittest.main()
