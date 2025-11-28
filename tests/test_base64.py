import base64

# Test b64encode - Python requires bytes input
text = b"Hello, World!"
encoded = base64.b64encode(text)
print(encoded)

# Test b64decode
decoded = base64.b64decode(encoded)
print(decoded)
