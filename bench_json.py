import json

data = {"name": "PyAOT", "version": 1, "count": 100}

# Test dumps (just correctness)
result = json.dumps(data)
print(result)

# Test loads (just correctness)
parsed = json.loads(result)
print(parsed["name"])
print(parsed["version"])
print(parsed["count"])
