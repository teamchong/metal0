"""Base64 roundtrip tests for metal0 C interop"""
import base64
import unittest

class TestB64RoundtripShort(unittest.TestCase):
    def test_roundtrip_a(self):
        original = b"a"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_ab(self):
        original = b"ab"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_abc(self):
        original = b"abc"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_hello(self):
        original = b"hello"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_world(self):
        original = b"world"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

class TestB64RoundtripMedium(unittest.TestCase):
    def test_roundtrip_sentence(self):
        original = b"The quick brown fox"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_numbers(self):
        original = b"1234567890"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_mixed(self):
        original = b"abc123xyz"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_roundtrip_special(self):
        original = b"hello world!"
        encoded = base64.b64encode(original)
        decoded = base64.b64decode(encoded)
        self.assertEqual(decoded, original)

class TestB64UrlsafeRoundtrip(unittest.TestCase):
    def test_urlsafe_a(self):
        original = b"a"
        encoded = base64.urlsafe_b64encode(original)
        decoded = base64.urlsafe_b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_urlsafe_ab(self):
        original = b"ab"
        encoded = base64.urlsafe_b64encode(original)
        decoded = base64.urlsafe_b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_urlsafe_abc(self):
        original = b"abc"
        encoded = base64.urlsafe_b64encode(original)
        decoded = base64.urlsafe_b64decode(encoded)
        self.assertEqual(decoded, original)

    def test_urlsafe_hello(self):
        original = b"hello"
        encoded = base64.urlsafe_b64encode(original)
        decoded = base64.urlsafe_b64decode(encoded)
        self.assertEqual(decoded, original)

class TestB64Encode(unittest.TestCase):
    def test_encode_hello(self):
        result = base64.b64encode(b"hello")
        self.assertEqual(result, b"aGVsbG8=")

    def test_encode_abc(self):
        result = base64.b64encode(b"abc")
        self.assertEqual(result, b"YWJj")

    def test_encode_a(self):
        result = base64.b64encode(b"a")
        self.assertEqual(result, b"YQ==")

    def test_encode_ab(self):
        result = base64.b64encode(b"ab")
        self.assertEqual(result, b"YWI=")

if __name__ == "__main__":
    unittest.main()
