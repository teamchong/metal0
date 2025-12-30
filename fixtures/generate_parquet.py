#!/usr/bin/env python3
"""
Generate Parquet test fixture files.

This script creates .parquet files with known content for testing the
Zig Parquet implementation.

Usage:
    cd fixtures
    pip install pyarrow
    python generate_parquet.py
"""

import os
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

# Output directory
FIXTURES_DIR = Path(__file__).parent.parent / "tests" / "fixtures"


def generate_simple_parquet():
    """Generate a simple Parquet file with all types."""
    table = pa.table({
        "id": pa.array([1, 2, 3, 4, 5], type=pa.int64()),
        "name": pa.array(["alice", "bob", "charlie", "diana", "eve"], type=pa.utf8()),
        "value": pa.array([1.1, 2.2, 3.3, 4.4, 5.5], type=pa.float64()),
    })

    # Default (dictionary encoded, uncompressed)
    path = FIXTURES_DIR / "simple.parquet"
    pq.write_table(table, path, compression=None)
    print(f"Generated: {path}")

    # PLAIN encoding only (no dictionary, uncompressed)
    path = FIXTURES_DIR / "simple_plain.parquet"
    pq.write_table(table, path, use_dictionary=False, compression=None)
    print(f"Generated: {path}")

    # Snappy compression (dictionary encoded)
    path = FIXTURES_DIR / "simple_snappy.parquet"
    pq.write_table(table, path, compression="snappy")
    print(f"Generated: {path}")

    # PLAIN + Snappy compression
    path = FIXTURES_DIR / "simple_plain_snappy.parquet"
    pq.write_table(table, path, use_dictionary=False, compression="snappy")
    print(f"Generated: {path}")


def print_parquet_info(path: Path):
    """Print information about a Parquet file."""
    pf = pq.ParquetFile(path)
    print(f"\n{path.name}:")
    print(f"  Size: {path.stat().st_size} bytes")
    print(f"  Schema: {pf.schema_arrow}")
    print(f"  Num rows: {pf.metadata.num_rows}")
    print(f"  Num row groups: {pf.metadata.num_row_groups}")

    for i in range(pf.metadata.num_row_groups):
        rg = pf.metadata.row_group(i)
        for j in range(rg.num_columns):
            col = rg.column(j)
            print(f"  Column {j}: compression={col.compression}, encoding={col.encodings}")


def main():
    print("Parquet Test Fixture Generator")
    print("=" * 40)

    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)

    generate_simple_parquet()

    print("\n" + "=" * 40)
    print("File Information:")

    for path in sorted(FIXTURES_DIR.glob("*.parquet")):
        print_parquet_info(path)


if __name__ == "__main__":
    main()
