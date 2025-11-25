"""
End-to-end JSON benchmark - Simple program for hyperfine
JSON parsing in tight loop
Runs ~60 seconds on CPython for statistical significance
"""
import json

# Simulate API workflow: parse JSON response repeatedly
response_data = '{"id": 123, "status": "success", "data": {"count": 42}}'

for i in range(10_000_000):
    # Parse JSON response
    obj = json.loads(response_data)

print("Done")
