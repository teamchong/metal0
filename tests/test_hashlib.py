import hashlib

# Test MD5
h = hashlib.md5()
h.update(b"hello")
print("MD5 digest:", h.hexdigest())

# Test SHA1
h = hashlib.sha1()
h.update(b"hello")
print("SHA1 digest:", h.hexdigest())

# Test SHA256
h = hashlib.sha256()
h.update(b"hello")
print("SHA256 digest:", h.hexdigest())

# Test SHA512
h = hashlib.sha512()
h.update(b"hello")
print("SHA512 digest:", h.hexdigest())

# Test new()
h = hashlib.new("md5")
h.update(b"hello")
print("new('md5') digest:", h.hexdigest())
