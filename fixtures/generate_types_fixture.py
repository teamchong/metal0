#!/usr/bin/env python3
"""
Generate Lance test fixtures for additional data types testing.

Creates a Lance file with int32, float32, and bool columns.
"""

import pyarrow as pa
import lance
import os
import json
import glob

def main():
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'tests', 'fixtures', 'better-sqlite3')
    os.makedirs(output_dir, exist_ok=True)

    # Fixture for additional types testing
    print("Creating 'types_test' fixture with int32, float32, bool columns...")

    # Create data with various types
    types_data = {
        'i32_col': pa.array([1, 2, 3, -1, 0], type=pa.int32()),
        'f32_col': pa.array([1.5, 2.5, 3.5, -1.5, 0.0], type=pa.float32()),
        'bool_col': pa.array([True, False, True, False, True], type=pa.bool_()),
        'i64_col': pa.array([100, 200, 300, -100, 0], type=pa.int64()),  # For comparison
        'name': pa.array(['apple', 'banana', 'cherry', 'date', 'elderberry'], type=pa.string()),
    }

    schema = pa.schema([
        ('i32_col', pa.int32()),
        ('f32_col', pa.float32()),
        ('bool_col', pa.bool_()),
        ('i64_col', pa.int64()),
        ('name', pa.string()),
    ])

    table = pa.Table.from_pydict(types_data, schema=schema)
    types_path = os.path.join(output_dir, 'types_test.lance')
    lance.write_dataset(table, types_path, mode='overwrite')

    print(f"✓ Created {types_path}")
    print(f"  - Rows: {len(table)}")
    print(f"  - Columns: {table.schema.names}")
    print(f"  - Schema: {table.schema}")

    # Get the actual Lance file path
    lance_files = glob.glob(os.path.join(types_path, 'data', '*.lance'))

    # Update paths.json with the new fixture
    config_path = os.path.join(output_dir, 'paths.json')

    # Load existing paths if exists
    paths = {}
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            paths = json.load(f)

    if lance_files:
        paths['types_test'] = lance_files[0]
        print(f"  - Lance file: {lance_files[0]}")

    with open(config_path, 'w') as f:
        json.dump(paths, f, indent=2)
    print(f"  - Updated path config: {config_path}")

    print("\nFixture generated successfully!")
    print("\nExpected query results:")
    print("  SELECT i32_col FROM table -> [1, 2, 3, -1, 0]")
    print("  SELECT f32_col FROM table -> [1.5, 2.5, 3.5, -1.5, 0.0]")
    print("  SELECT bool_col FROM table -> [true, false, true, false, true]")
    print("  SELECT * FROM table WHERE bool_col = true -> 3 rows")

if __name__ == '__main__':
    main()
