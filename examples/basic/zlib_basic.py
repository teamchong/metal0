import zlib

data = b"Hello, World!" * 100
compressed = zlib.compress(data)
print(f"Original: {len(data)} bytes")
print(f"Compressed: {len(compressed)} bytes")

decompressed = zlib.decompress(compressed)
assert decompressed == data
print("Compression successful")
