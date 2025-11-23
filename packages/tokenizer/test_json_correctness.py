#!/usr/bin/env python3
"""
Comprehensive JSON correctness test - Generate test cases for PyAOT
Compares PyAOT JSON output against Python's json module
"""

import json
import sys

# Test cases covering all JSON types
test_cases = [
    # Primitives
    ("null", None),
    ("true", True),
    ("false", False),

    # Numbers
    ("zero", 0),
    ("positive_int", 42),
    ("negative_int", -123),
    ("large_int", 999999999),

    # Strings
    ("empty_string", ""),
    ("simple_string", "hello"),
    ("string_with_spaces", "hello world"),
    ("string_with_newline", "hello\nworld"),
    ("string_with_tab", "hello\tworld"),
    ("string_with_quotes", 'hello "world"'),
    ("string_with_backslash", "hello\\world"),
    ("string_with_unicode", "hello 世界"),

    # Arrays
    ("empty_array", []),
    ("simple_array", [1, 2, 3]),
    ("mixed_array", [1, "two", True, None]),
    ("nested_array", [[1, 2], [3, 4]]),

    # Objects
    ("empty_object", {}),
    ("simple_object", {"name": "test", "value": 123}),
    ("nested_object", {"outer": {"inner": "value"}}),
    ("complex_object", {
        "string": "value",
        "number": 42,
        "bool": True,
        "null": None,
        "array": [1, 2, 3],
        "object": {"nested": "data"}
    }),
]

print("# JSON Correctness Test Cases")
print("# Format: name | json_string | expected_output")
print()

for name, value in test_cases:
    json_str = json.dumps(value)
    expected = json.dumps(value, separators=(',', ':'))  # Compact format
    print(f"{name}|{json_str}|{expected}")
