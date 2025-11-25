"""
JSON parsing benchmark - Simple program for hyperfine
Runs ~60 seconds on CPython for statistical significance
"""
import json

# Small JSON - parse 10 million times for ~60s on CPython
data = '{"id": 123, "name": "test", "active": true, "score": 95.5}'

for _ in range(10000000):
    obj = json.loads(data)

print("Done")
