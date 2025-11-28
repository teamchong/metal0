# Simple stdlib tests for PyAOT
# Tests real functionality of implemented modules

import json
import math
import re
import os
import sys
import string

# ===== JSON Module =====
print("Testing json module...")

# json.dumps with dict
d = {"key": "value", "num": 42}
s = json.dumps(d)
print(s)

# json.loads
parsed = json.loads('{"a": 1, "b": 2}')
print("json.loads works")

# ===== Math Module =====
print("Testing math module...")

# Basic math functions
print(math.sqrt(16.0))  # 4.0
print(math.floor(3.7))  # 3
print(math.ceil(3.2))   # 4
print(math.fabs(-5.0))  # 5.0
print(math.pow(2.0, 3.0))  # 8.0

# Trigonometric functions
print(math.sin(0.0))  # 0.0
print(math.cos(0.0))  # 1.0

# Constants
print(math.pi)  # 3.14159...
print(math.e)   # 2.71828...

# ===== String Module =====
print("Testing string module...")
print(string.ascii_lowercase)
print(string.ascii_uppercase)
print(string.digits)

# ===== RE Module =====
print("Testing re module...")

# re.match
m = re.match("hello", "hello world")
print("re.match: found" if m else "re.match: not found")

# re.search
s = re.search("world", "hello world")
print("re.search: found" if s else "re.search: not found")

# ===== OS Module =====
print("Testing os module...")
print(os.getcwd())
print(os.name)

# ===== Sys Module =====
print("Testing sys module...")
print(sys.platform)
print(sys.version_info.major)

print("All stdlib tests completed!")
