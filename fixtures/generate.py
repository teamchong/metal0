#!/usr/bin/env python3
"""
Generate Lance test fixture files.

This script creates .lance files with known content for testing the
Zig LanceQL implementation. Each file has an accompanying .expected.json
file containing the expected values.

Usage:
    cd fixtures
    pip install -r requirements.txt
    python generate.py

Output:
    tests/fixtures/simple_int64.lance
    tests/fixtures/simple_int64.expected.json
    tests/fixtures/mixed_types.lance
    tests/fixtures/mixed_types.expected.json
    ...
"""

import json
import os
import shutil
from pathlib import Path

import lance
import pyarrow as pa

# Output directory
FIXTURES_DIR = Path(__file__).parent.parent / "tests" / "fixtures"


def ensure_clean_dir():
    """Ensure the fixtures directory exists and is clean."""
    if FIXTURES_DIR.exists():
        shutil.rmtree(FIXTURES_DIR)
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)

    # Create .gitkeep
    (FIXTURES_DIR / ".gitkeep").touch()


def write_expected(name: str, expected: dict):
    """Write expected values to JSON file."""
    path = FIXTURES_DIR / f"{name}.expected.json"
    with open(path, "w") as f:
        json.dump(expected, f, indent=2)
    print(f"  -> {path}")


def generate_simple_int64():
    """Generate a simple Lance file with a single int64 column."""
    name = "simple_int64"
    print(f"Generating {name}...")

    values = [1, 2, 3, 4, 5]
    table = pa.table({
        "id": pa.array(values, type=pa.int64()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["id"],
        "row_count": len(values),
        "id": values,
    })


def generate_simple_float64():
    """Generate a Lance file with a single float64 column."""
    name = "simple_float64"
    print(f"Generating {name}...")

    values = [1.5, 2.5, 3.5, 4.5, 5.5]
    table = pa.table({
        "value": pa.array(values, type=pa.float64()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["value"],
        "row_count": len(values),
        "value": values,
    })


def generate_mixed_types():
    """Generate a Lance file with multiple column types."""
    name = "mixed_types"
    print(f"Generating {name}...")

    ids = [1, 2, 3]
    values = [1.5, 2.5, 3.5]
    names = ["alice", "bob", "charlie"]

    table = pa.table({
        "id": pa.array(ids, type=pa.int64()),
        "value": pa.array(values, type=pa.float64()),
        "name": pa.array(names, type=pa.utf8()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["id", "value", "name"],
        "row_count": 3,
        "id": ids,
        "value": values,
        "name": names,
    })


def generate_nulls():
    """Generate a Lance file with null values."""
    name = "with_nulls"
    print(f"Generating {name}...")

    ids = [1, None, 3, None, 5]
    values = [1.5, 2.5, None, 4.5, None]

    table = pa.table({
        "id": pa.array(ids, type=pa.int64()),
        "value": pa.array(values, type=pa.float64()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["id", "value"],
        "row_count": 5,
        "id": ids,
        "value": values,
        "null_count_id": 2,
        "null_count_value": 2,
    })


def generate_empty():
    """Generate an empty Lance file."""
    name = "empty"
    print(f"Generating {name}...")

    table = pa.table({
        "id": pa.array([], type=pa.int64()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["id"],
        "row_count": 0,
        "id": [],
    })


def generate_large():
    """Generate a larger Lance file for performance testing."""
    name = "large"
    print(f"Generating {name}...")

    import numpy as np

    n = 10000
    ids = list(range(n))
    values = np.random.random(n).tolist()

    table = pa.table({
        "id": pa.array(ids, type=pa.int64()),
        "value": pa.array(values, type=pa.float64()),
    })

    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(table, str(path), mode="overwrite")
    print(f"  -> {path}")

    # For large files, just store summary statistics
    write_expected(name, {
        "columns": ["id", "value"],
        "row_count": n,
        "id_sum": sum(ids),
        "id_min": 0,
        "id_max": n - 1,
    })


def generate_multiple_batches():
    """Generate a Lance file with multiple row groups/batches."""
    name = "multiple_batches"
    print(f"Generating {name}...")

    # Create multiple batches
    batch1 = pa.table({"id": pa.array([1, 2, 3], type=pa.int64())})
    batch2 = pa.table({"id": pa.array([4, 5, 6], type=pa.int64())})
    batch3 = pa.table({"id": pa.array([7, 8, 9], type=pa.int64())})

    # Write with small max_rows_per_file to force multiple fragments
    path = FIXTURES_DIR / f"{name}.lance"
    lance.write_dataset(batch1, str(path), mode="overwrite")
    lance.write_dataset(batch2, str(path), mode="append")
    lance.write_dataset(batch3, str(path), mode="append")
    print(f"  -> {path}")

    write_expected(name, {
        "columns": ["id"],
        "row_count": 9,
        "id": [1, 2, 3, 4, 5, 6, 7, 8, 9],
    })


def print_file_info(name: str):
    """Print information about a generated Lance file."""
    path = FIXTURES_DIR / f"{name}.lance"
    ds = lance.dataset(str(path))

    print(f"\n{name}:")
    print(f"  Schema: {ds.schema}")
    print(f"  Num rows: {ds.count_rows()}")
    print(f"  Num fragments: {len(ds.get_fragments())}")

    # Print file size
    total_size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    print(f"  Total size: {total_size:,} bytes")


def main():
    print("LanceQL Test Fixture Generator")
    print("=" * 40)

    ensure_clean_dir()
    print(f"Output directory: {FIXTURES_DIR}\n")

    # Generate all fixtures
    generate_simple_int64()
    generate_simple_float64()
    generate_mixed_types()
    generate_nulls()
    generate_empty()
    generate_large()
    generate_multiple_batches()

    print("\n" + "=" * 40)
    print("File Information:")

    # Print info for each generated file
    for name in ["simple_int64", "simple_float64", "mixed_types", "with_nulls",
                 "empty", "large", "multiple_batches"]:
        print_file_info(name)

    print("\n" + "=" * 40)
    print("Done! Generated test fixtures in:", FIXTURES_DIR)


if __name__ == "__main__":
    main()
