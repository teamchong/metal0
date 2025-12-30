#!/usr/bin/env python3
"""
Generate Lance test fixtures matching better-sqlite3 test data.

This script creates Lance files that match the test data structure used in the
official better-sqlite3 test suite, allowing us to run their tests against our
read-only Lance implementation.
"""

import pyarrow as pa
import lance
import os

def main():
    output_dir = os.path.join(os.path.dirname(__file__), '..', 'tests', 'fixtures', 'better-sqlite3')
    os.makedirs(output_dir, exist_ok=True)

    # Fixture 1: "entries" table (simplified - no BLOB for now)
    # Used in: 21.statement.get.js, 22.statement.all.js, 23.statement.iterate.js
    # Schema: a TEXT, b INTEGER, c REAL, e TEXT (skip 'd' BLOB - not supported yet)
    # Data: 10 rows with b = 1-10, a = 'foo', c = 3.14, e = NULL
    print("Creating 'entries' fixture (simplified without BLOB)...")

    entries_data = {
        'a': ['foo'] * 10,
        'b': list(range(1, 11)),  # 1, 2, 3, ..., 10
        'c': [3.14] * 10,
        'e': [None] * 10,  # NULL
    }

    schema = pa.schema([
        ('a', pa.string()),
        ('b', pa.int64()),
        ('c', pa.float64()),
        ('e', pa.string()),
    ])

    table = pa.Table.from_pydict(entries_data, schema=schema)
    entries_path = os.path.join(output_dir, 'entries.lance')
    lance.write_dataset(table, entries_path, mode='overwrite')

    print(f"✓ Created {entries_path}")
    print(f"  - Rows: {len(table)}")
    print(f"  - Columns: {table.schema.names}")
    print(f"  - Schema: {table.schema}")

    # Get the actual Lance file path (not the directory)
    # Lance datasets have a structure like: entries.lance/data/<fragment>.lance
    import glob
    lance_files = glob.glob(os.path.join(entries_path, 'data', '*.lance'))
    if lance_files:
        print(f"  - Lance file: {lance_files[0]}")

        # Write a config file with the path
        config_path = os.path.join(output_dir, 'paths.json')
        import json
        with open(config_path, 'w') as f:
            json.dump({
                'entries': lance_files[0]
            }, f, indent=2)
        print(f"  - Wrote path config to: {config_path}")

    print("\nFixtures generated successfully!")
    print("\nUsage in tests:")
    print("  const Database = require('../src/index.js');")
    print("  const paths = require('./fixtures/better-sqlite3/paths.json');")
    print("  const db = new Database(paths.entries);")

if __name__ == '__main__':
    main()
