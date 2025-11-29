"""Base64 standard alphabet tests for metal0 C interop"""
import base64
import unittest

class TestB64EncodeValues(unittest.TestCase):
    def test_encode_a(self):
        self.assertEqual(base64.b64encode(b"a"), b"YQ==")

    def test_encode_ab(self):
        self.assertEqual(base64.b64encode(b"ab"), b"YWI=")

    def test_encode_abc(self):
        self.assertEqual(base64.b64encode(b"abc"), b"YWJj")

    def test_encode_abcd(self):
        self.assertEqual(base64.b64encode(b"abcd"), b"YWJjZA==")

    def test_encode_test(self):
        self.assertEqual(base64.b64encode(b"test"), b"dGVzdA==")

    def test_encode_hello(self):
        self.assertEqual(base64.b64encode(b"hello"), b"aGVsbG8=")

    def test_encode_world(self):
        self.assertEqual(base64.b64encode(b"world"), b"d29ybGQ=")

    def test_encode_python(self):
        self.assertEqual(base64.b64encode(b"python"), b"cHl0aG9u")

class TestB64DecodeValues(unittest.TestCase):
    def test_decode_a(self):
        self.assertEqual(base64.b64decode(b"YQ=="), b"a")

    def test_decode_ab(self):
        self.assertEqual(base64.b64decode(b"YWI="), b"ab")

    def test_decode_abc(self):
        self.assertEqual(base64.b64decode(b"YWJj"), b"abc")

    def test_decode_abcd(self):
        self.assertEqual(base64.b64decode(b"YWJjZA=="), b"abcd")

    def test_decode_test(self):
        self.assertEqual(base64.b64decode(b"dGVzdA=="), b"test")

    def test_decode_hello(self):
        self.assertEqual(base64.b64decode(b"aGVsbG8="), b"hello")

    def test_decode_world(self):
        self.assertEqual(base64.b64decode(b"d29ybGQ="), b"world")

    def test_decode_python(self):
        self.assertEqual(base64.b64decode(b"cHl0aG9u"), b"python")

class TestB64Numbers(unittest.TestCase):
    def test_encode_0(self):
        self.assertEqual(base64.b64encode(b"0"), b"MA==")

    def test_encode_123(self):
        self.assertEqual(base64.b64encode(b"123"), b"MTIz")

    def test_encode_9876(self):
        self.assertEqual(base64.b64encode(b"9876"), b"OTg3Ng==")

    def test_decode_0(self):
        self.assertEqual(base64.b64decode(b"MA=="), b"0")

    def test_decode_123(self):
        self.assertEqual(base64.b64decode(b"MTIz"), b"123")

    def test_decode_9876(self):
        self.assertEqual(base64.b64decode(b"OTg3Ng=="), b"9876")

class TestB64Special(unittest.TestCase):
    def test_encode_space(self):
        self.assertEqual(base64.b64encode(b" "), b"IA==")

    def test_encode_exclaim(self):
        self.assertEqual(base64.b64encode(b"!"), b"IQ==")

    def test_encode_at(self):
        self.assertEqual(base64.b64encode(b"@"), b"QA==")

    def test_encode_hash(self):
        self.assertEqual(base64.b64encode(b"#"), b"Iw==")

    def test_decode_space(self):
        self.assertEqual(base64.b64decode(b"IA=="), b" ")

    def test_decode_exclaim(self):
        self.assertEqual(base64.b64decode(b"IQ=="), b"!")

class TestUrlsafeValues(unittest.TestCase):
    def test_urlsafe_encode_hello(self):
        self.assertEqual(base64.urlsafe_b64encode(b"hello"), b"aGVsbG8=")

    def test_urlsafe_encode_world(self):
        self.assertEqual(base64.urlsafe_b64encode(b"world"), b"d29ybGQ=")

    def test_urlsafe_decode_hello(self):
        self.assertEqual(base64.urlsafe_b64decode(b"aGVsbG8="), b"hello")

    def test_urlsafe_decode_world(self):
        self.assertEqual(base64.urlsafe_b64decode(b"d29ybGQ="), b"world")

class TestB64Long(unittest.TestCase):
    def test_encode_sentence(self):
        result = base64.b64encode(b"The quick brown fox")
        self.assertEqual(result, b"VGhlIHF1aWNrIGJyb3duIGZveA==")

    def test_decode_sentence(self):
        result = base64.b64decode(b"VGhlIHF1aWNrIGJyb3duIGZveA==")
        self.assertEqual(result, b"The quick brown fox")

    def test_encode_longer(self):
        result = base64.b64encode(b"Hello World 123")
        self.assertEqual(result, b"SGVsbG8gV29ybGQgMTIz")

    def test_decode_longer(self):
        result = base64.b64decode(b"SGVsbG8gV29ybGQgMTIz")
        self.assertEqual(result, b"Hello World 123")

if __name__ == "__main__":
    unittest.main()
