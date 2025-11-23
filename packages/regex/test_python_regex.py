import re

# Test what Python considers whitespace
whitespace_chars = []
for i in range(256):
    c = chr(i)
    if re.match(r'\s', c):
        whitespace_chars.append((i, repr(c)))

print("Python \\s matches:")
for code, char in whitespace_chars:
    print(f"  {code:3d} {char}")

# Test digit
print("\nPython \\d matches: [0-9] (48-57)")

# Test word
word_chars = []
for i in range(256):
    c = chr(i)
    if re.match(r'\w', c):
        word_chars.append(i)
print(f"\nPython \\w matches {len(word_chars)} chars:")
print(f"  0-9: {list(range(48, 58))}")
print(f"  A-Z: {list(range(65, 91))}")
print(f"  a-z: {list(range(97, 123))}")
print(f"  underscore: [95]")
