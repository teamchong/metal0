# pyaot: hmac.new returns hex string directly (simplified API)
import hmac

# Test hmac.new() - compute HMAC-SHA256 (returns hex digest directly)
key = b"secret_key"
msg = b"Hello, World!"
result = hmac.new(key, msg, "sha256")  # type: ignore
print("HMAC:", result)

# Test hmac.compare_digest with strings
a = "test_string"
b = "test_string"
is_equal = hmac.compare_digest(a, b)
print("Compare equal:", is_equal)
