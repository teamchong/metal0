#!/usr/bin/env python3
"""Convert PyAOT JSON with raw bytes to proper UTF-8 JSON"""

import json
import sys

# Read as binary
with open("pyaot_trained.json", "rb") as f:
    data = f.read()

# Try to decode with error replacement
json_str = data.decode('utf-8', errors='replace')
pyaot = json.loads(json_str)

# Re-encode properly
with open("pyaot_trained_fixed.json", "w", encoding='utf-8') as f:
    json.dump(pyaot, f, ensure_ascii=False, indent=2)

print("✅ Fixed and saved to pyaot_trained_fixed.json")
