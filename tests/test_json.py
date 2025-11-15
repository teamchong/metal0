"""Test JSON module - loads() and dumps()"""
import json

# Test 1: Parse null
result = json.loads("null")
assert result is None, f"Expected None, got {result}"
print("✓ Parse null")

# Test 2: Parse boolean
assert json.loads("true") == True
assert json.loads("false") == False
print("✓ Parse booleans")

# Test 3: Parse numbers
assert json.loads("42") == 42
assert json.loads("-123") == -123
assert json.loads("0") == 0
print("✓ Parse numbers")

# Test 4: Parse strings
assert json.loads('"hello"') == "hello"
assert json.loads('""') == ""
assert json.loads('"hello world"') == "hello world"
print("✓ Parse strings")

# Test 5: Parse arrays
nums = json.loads("[1, 2, 3]")
assert len(nums) == 3
assert nums[0] == 1
assert nums[1] == 2
assert nums[2] == 3
print("✓ Parse arrays")

# Test 6: Parse empty arrays
empty = json.loads("[]")
assert len(empty) == 0
print("✓ Parse empty arrays")

# Test 7: Parse objects
data = json.loads('{"name": "PyAOT", "count": 3}')
assert data["name"] == "PyAOT"
assert data["count"] == 3
print("✓ Parse objects")

# Test 8: Parse empty objects
empty_obj = json.loads("{}")
assert len(empty_obj) == 0
print("✓ Parse empty objects")

# Test 9: Parse nested structures
nested = json.loads('{"items": [1, 2, 3], "meta": {"count": 3}}')
assert len(nested["items"]) == 3
assert nested["items"][0] == 1
assert nested["meta"]["count"] == 3
print("✓ Parse nested structures")

# Test 10: Stringify numbers
assert json.dumps(42) == "42"
assert json.dumps(-123) == "-123"
print("✓ Stringify numbers")

# Test 11: Stringify strings
assert json.dumps("hello") == '"hello"'
assert json.dumps("") == '""'
print("✓ Stringify strings")

# Test 12: Stringify arrays
assert json.dumps([1, 2, 3]) == "[1,2,3]"
assert json.dumps([]) == "[]"
print("✓ Stringify arrays")

# Test 13: Stringify objects
result = json.dumps({"name": "PyAOT"})
assert '"name"' in result
assert '"PyAOT"' in result
print("✓ Stringify objects")

# Test 14: Round-trip test
original = {"test": [1, 2, 3], "nested": {"key": "value"}}
json_str = json.dumps(original)
parsed = json.loads(json_str)
assert len(parsed["test"]) == 3
assert parsed["test"][0] == 1
assert parsed["nested"]["key"] == "value"
print("✓ Round-trip conversion")

print("\n✅ All JSON tests passed!")
