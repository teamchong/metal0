"""JSON module demonstration - native SIMD-optimized JSON parsing"""
import json

# Basic parsing
num = json.loads("42")
print(num)  # 42

text = json.loads('"hello world"')
print(text)  # hello world

# Parse array
numbers = json.loads("[1, 2, 3, 4, 5]")
print(numbers[0])  # 1
print(numbers[2])  # 3

# Parse object
data = json.loads('{"name": "PyAOT", "version": 1}')
print(data["name"])  # PyAOT
print(data["version"])  # 1

# Stringify
json_str = json.dumps([1, 2, 3])
print(json_str)  # [1,2,3]

obj_str = json.dumps({"test": "value"})
print(obj_str)  # {"test":"value"}

# Round-trip
original = {"items": [1, 2, 3], "count": 3}
serialized = json.dumps(original)
deserialized = json.loads(serialized)
print(deserialized["count"])  # 3
print(deserialized["items"][1])  # 2

print("JSON demo complete!")
