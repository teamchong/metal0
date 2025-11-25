# Test string trim methods (lstrip, rstrip, strip) don't cause memory errors

# Test lstrip
result1 = "  hello  ".lstrip()
assert result1 == "hello  "
print("lstrip: PASS")

# Test rstrip
result2 = "  hello  ".rstrip()
assert result2 == "  hello"
print("rstrip: PASS")

# Test strip
result3 = "  hello  ".strip()
assert result3 == "hello"
print("strip: PASS")

# Test print with lstrip (THIS WAS CRASHING BEFORE FIX)
print("  hello  ".lstrip())

# Test print with rstrip (THIS WAS CRASHING BEFORE FIX)
print("  hello  ".rstrip())

# Test print with strip
print("  hello  ".strip())

# Test chained methods
result4 = "  hello  ".strip().upper()
assert result4 == "HELLO"
print("chained: PASS")

# Test variable assignment
x = "  world  ".lstrip()
print(x)

print("All tests passed!")
