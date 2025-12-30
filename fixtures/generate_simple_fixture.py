#!/usr/bin/env python3
"""
Generate a super simple Lance test fixture for initial testing.
"""

import pyarrow as pa
import lance
import os

output_dir = os.path.join(os.path.dirname(__file__), '..', 'tests', 'fixtures', 'better-sqlite3')
os.makedirs(output_dir, exist_ok=True)

# Super simple: just int and string, NO NULL values
entries_data = {
    'a': ['foo', 'bar', 'baz', 'qux', 'quux', 'corge', 'grault', 'garply', 'waldo', 'fred'],
    'b': list(range(1, 11)),  # 1, 2, 3, ..., 10
}

schema = pa.schema([
    ('a', pa.string()),
    ('b', pa.int64()),
])

table = pa.Table.from_pydict(entries_data, schema=schema)
entries_path = os.path.join(output_dir, 'simple.lance')
lance.write_dataset(table, entries_path, mode='overwrite')

print(f"✓ Created simple.lance with {len(table)} rows")
print(f"  Schema: {table.schema}")

# Get Lance file path
import glob
lance_files = glob.glob(os.path.join(entries_path, 'data', '*.lance'))
print(f"  Lance file: {lance_files[0]}")

# Write config
import json
config_path = os.path.join(output_dir, 'paths.json')
with open(config_path, 'w') as f:
    json.dump({'simple': lance_files[0]}, f, indent=2)
print(f"  Config: {config_path}")
