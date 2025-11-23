import re

# Test ASCII mode (re.ASCII flag)
print("Python \\w with ASCII flag:")
word_count = 0
for i in range(256):
    c = chr(i)
    if re.match(r'\w', c, re.ASCII):
        word_count += 1
print(f"  Matches {word_count} chars (should be 63: a-z A-Z 0-9 _)")

print("\nPython \\s with ASCII flag:")
for i in range(256):
    c = chr(i)
    if re.match(r'\s', c, re.ASCII):
        print(f"  {i:3d} {repr(c)}")
        
print("\nPython \\d with ASCII flag:")
digit_count = 0
for i in range(256):
    c = chr(i)
    if re.match(r'\d', c, re.ASCII):
        digit_count += 1
print(f"  Matches {digit_count} chars (should be 10: 0-9)")
