# Test comptime string evaluation
# String methods should be evaluated at compile time

s1 = "hello".upper()
s2 = "WORLD".lower()
s3 = "  trim  ".strip()
s4 = "hello" + " " + "world"
s5 = "abc".replace("b", "X")

print(s1)  # Should print: HELLO
print(s2)  # Should print: world
print(s3)  # Should print: trim
print(s4)  # Should print: hello world
print(s5)  # Should print: aXc
