import struct

# Test calcsize
size_i = struct.calcsize("i")
print("Size of 'i':", size_i)

size_iih = struct.calcsize("iih")
print("Size of 'iih':", size_iih)
