"""Benchmark PyAOT's JSON implementation"""
import json

# Simple JSON string
json_data = '{"name":"PyAOT","version":"1.0.0","performance":{"encoding":"2.489s","correctness":true},"features":["BPE","Training","WASM"]}'

# Parse and stringify 10000 times
for i in range(10000):
    parsed = json.loads(json_data)
    stringified = json.dumps(parsed)

print("Done!")
