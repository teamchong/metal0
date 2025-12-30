#!/usr/bin/env python3
"""
Generate Lance test fixtures for DISTINCT testing.

Creates a Lance file with duplicate values to test SELECT DISTINCT.
"""

import pyarrow as pa
import lance
import os
import json
import glob

def main():
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'tests', 'fixtures', 'better-sqlite3')
    os.makedirs(output_dir, exist_ok=True)

    # Fixture for DISTINCT testing
    # Data with intentional duplicates
    print("Creating 'distinct_test' fixture with duplicate values...")

    # Create data with duplicates for DISTINCT testing
    distinct_data = {
        'category': ['A', 'B', 'A', 'C', 'B', 'A', 'C', 'A'],  # 4 unique: A, B, C
        'value': [1, 2, 1, 3, 2, 1, 3, 1],                      # 3 unique: 1, 2, 3
        'name': ['foo', 'bar', 'foo', 'baz', 'bar', 'foo', 'baz', 'foo'],  # 3 unique
    }

    schema = pa.schema([
        ('category', pa.string()),
        ('value', pa.int64()),
        ('name', pa.string()),
    ])

    table = pa.Table.from_pydict(distinct_data, schema=schema)
    distinct_path = os.path.join(output_dir, 'distinct_test.lance')
    lance.write_dataset(table, distinct_path, mode='overwrite')

    print(f"✓ Created {distinct_path}")
    print(f"  - Rows: {len(table)}")
    print(f"  - Columns: {table.schema.names}")
    print(f"  - Data (category): {distinct_data['category']}")
    print(f"  - Data (value): {distinct_data['value']}")
    print(f"  - Data (name): {distinct_data['name']}")

    # Get the actual Lance file path
    lance_files = glob.glob(os.path.join(distinct_path, 'data', '*.lance'))

    # Update paths.json with the new fixture
    config_path = os.path.join(output_dir, 'paths.json')

    # Load existing paths if exists
    paths = {}
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            paths = json.load(f)

    if lance_files:
        paths['distinct_test'] = lance_files[0]
        print(f"  - Lance file: {lance_files[0]}")

    with open(config_path, 'w') as f:
        json.dump(paths, f, indent=2)
    print(f"  - Updated path config: {config_path}")

    print("\nFixture generated successfully!")
    print("\nExpected DISTINCT results:")
    print("  SELECT DISTINCT category -> ['A', 'B', 'C'] (3 unique)")
    print("  SELECT DISTINCT value -> [1, 2, 3] (3 unique)")
    print("  SELECT DISTINCT category, value -> 5 unique combinations")

if __name__ == '__main__':
    main()
