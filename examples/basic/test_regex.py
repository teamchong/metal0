import re

# Test 1: re.search()
result = re.search("world", "hello world")
print(result)  # Should print "world"

# Test 2: re.match() - matches at start
result2 = re.match("hello", "hello world")
print(result2)  # Should print "hello"

# Test 3: re.match() - doesn't match if not at start
result3 = re.match("world", "hello world")
print(result3)  # Should print None

# Test 4: re.compile()
pattern = re.compile("hello")
print("Regex pattern compiled successfully!")
