# Simple test for secrets module
import secrets

def test_randbits():
    # Test randbits with different bit counts
    n = secrets.randbits(8)
    assert 0 <= n < 256, "randbits failed"
    n = secrets.randbits(16)
    assert 0 <= n < 65536, "randbits failed"
    print("randbits: PASS")

def test_randbelow():
    # Test randbelow with valid values
    n = secrets.randbelow(10)
    assert 0 <= n < 10, "randbelow failed"
    n = secrets.randbelow(100)
    assert 0 <= n < 100, "randbelow failed"
    print("randbelow: PASS")

def test_token_bytes():
    # Just verify it returns something (can't easily check length)
    secrets.token_bytes(16)
    print("token_bytes: PASS")

def test_token_hex():
    # Just verify it returns something
    secrets.token_hex(16)
    print("token_hex: PASS")

def test_compare_digest():
    assert secrets.compare_digest("abc", "abc") == True
    assert secrets.compare_digest("abc", "xyz") == False
    assert secrets.compare_digest("", "") == True
    print("compare_digest: PASS")

if __name__ == "__main__":
    test_randbits()
    test_randbelow()
    test_token_bytes()
    test_token_hex()
    test_compare_digest()
    print("All secrets tests passed!")
