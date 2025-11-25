# Test stdlib imports for PyAOT
# Tests working functions from json, math, sys, re modules

import json
import math
import re

# json.dumps works with simple dict
data = {"name": "test"}
result = json.dumps(data)
print(result)

# math functions work
a = math.sqrt(25.0)
b = math.floor(3.7)
c = math.ceil(3.2)
print(a)
print(b)
print(c)

# re.match works
match = re.match("hello", "hello world")
print("re.match works")

# re.search works
found = re.search("world", "hello world")
print("re.search works")
