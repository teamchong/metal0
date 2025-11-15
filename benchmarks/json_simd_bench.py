"""
JSON SIMD parsing benchmark - Simple program for hyperfine
Tests SIMD-accelerated JSON parsing
Runs ~60 seconds on CPython for statistical significance
"""
import json

# Medium JSON - parse 1 million times for ~60s on CPython
data = '''
{
    "users": [
        {"id": 1, "name": "Alice", "email": "alice@example.com", "active": true},
        {"id": 2, "name": "Bob", "email": "bob@example.com", "active": false},
        {"id": 3, "name": "Charlie", "email": "charlie@example.com", "active": true}
    ],
    "total": 3,
    "timestamp": 1234567890
}
'''

for _ in range(1_000_000):
    obj = json.loads(data)

print("Done")
