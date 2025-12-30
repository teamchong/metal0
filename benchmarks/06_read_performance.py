#!/usr/bin/env python3
"""
Benchmark: Read Performance - LanceQL vs LanceDB
Compare raw read speed between our Zig-based reader and official lancedb.
"""

import time
import tempfile
import os
import sys
import numpy as np
import pyarrow as pa
import lancedb

# Add our Python package to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))
from metal0.lanceql import parquet as lanceql_pq

# Test configurations
ROWS_SMALL = 100_000
ROWS_MEDIUM = 1_000_000
WARMUP_ITERATIONS = 3
NUM_ITERATIONS = 10  # More iterations for statistical significance


def create_test_data(num_rows: int) -> pa.Table:
    """Create test dataset with various column types."""
    np.random.seed(42)
    return pa.table({
        "id": range(num_rows),
        "int_col": np.random.randint(0, 1000000, num_rows),
        "float_col": np.random.randn(num_rows),
        "str_col": [f"value_{i % 1000}" for i in range(num_rows)],
    })


def create_lance_file(tmpdir: str, data: pa.Table, name: str) -> str:
    """Create a Lance file using lancedb."""
    db_path = os.path.join(tmpdir, f"{name}_db")
    db = lancedb.connect(db_path)
    db.create_table("data", data)

    # Find the actual .lance file
    lance_files = []
    for root, dirs, files in os.walk(db_path):
        for f in files:
            if f.endswith('.lance'):
                lance_files.append(os.path.join(root, f))

    return db_path, lance_files[0] if lance_files else None


def compute_stats(times: list) -> dict:
    """Compute statistics from timing results."""
    times = np.array(times)
    return {
        "min": np.min(times),
        "median": np.median(times),
        "mean": np.mean(times),
        "p95": np.percentile(times, 95),
        "std": np.std(times),
    }


def benchmark_lancedb_read(db_path: str, warmup: int, iterations: int) -> dict:
    """Benchmark lancedb read performance."""
    # Warmup runs (not counted)
    for _ in range(warmup):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        _ = tbl.to_arrow()

    # Timed runs
    times = []
    for _ in range(iterations):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")

        start = time.perf_counter()
        result = tbl.to_arrow()
        elapsed = time.perf_counter() - start
        times.append(elapsed)

        row_count = len(result)

    stats = compute_stats(times)
    return {
        "reader": "lancedb",
        "row_count": row_count,
        **stats,
    }


def benchmark_lanceql_read(lance_file: str, warmup: int, iterations: int) -> dict:
    """Benchmark our LanceQL reader performance."""
    # Warmup runs (not counted)
    for _ in range(warmup):
        _ = lanceql_pq.read_table(lance_file)

    # Timed runs
    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = lanceql_pq.read_table(lance_file)
        elapsed = time.perf_counter() - start
        times.append(elapsed)

        row_count = len(result)

    stats = compute_stats(times)
    return {
        "reader": "lanceql",
        "row_count": row_count,
        **stats,
    }


def benchmark_column_projection(db_path: str, lance_file: str, columns: list, warmup: int, iterations: int) -> tuple:
    """Benchmark reading specific columns only."""
    # Warmup
    for _ in range(warmup):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        _ = tbl.to_arrow().select(columns)
        _ = lanceql_pq.read_table(lance_file, columns=columns)

    # lancedb
    lancedb_times = []
    for _ in range(iterations):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        start = time.perf_counter()
        # lancedb doesn't support column projection directly in to_arrow
        result = tbl.to_arrow().select(columns)
        lancedb_times.append(time.perf_counter() - start)

    # lanceql
    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = lanceql_pq.read_table(lance_file, columns=columns)
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "lancedb", **compute_stats(lancedb_times)},
        {"reader": "lanceql", **compute_stats(lanceql_times)},
    )


def benchmark_metadata_read(db_path: str, lance_file: str, warmup: int, iterations: int) -> tuple:
    """Benchmark metadata-only read (row count, schema)."""
    # Warmup
    for _ in range(warmup):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        _ = tbl.count_rows()
        _ = lanceql_pq.read_metadata(lance_file)

    # lancedb
    lancedb_times = []
    for _ in range(iterations):
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        start = time.perf_counter()
        row_count = tbl.count_rows()
        schema = tbl.schema
        lancedb_times.append(time.perf_counter() - start)

    # lanceql
    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        metadata = lanceql_pq.read_metadata(lance_file)
        row_count = metadata.num_rows
        schema = lanceql_pq.read_schema(lance_file)
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "lancedb", **compute_stats(lancedb_times)},
        {"reader": "lanceql", **compute_stats(lanceql_times)},
    )


def print_comparison(test_name: str, lancedb_result: dict, lanceql_result: dict):
    """Print comparison results with detailed statistics."""
    lancedb_median = lancedb_result["median"]
    lanceql_median = lanceql_result["median"]

    if lanceql_median < lancedb_median:
        speedup = lancedb_median / lanceql_median
        winner = "LanceQL"
    else:
        speedup = lanceql_median / lancedb_median
        winner = "lancedb"

    print(f"\n{test_name}:")
    print(f"  {'':20} {'lancedb':>12} {'LanceQL':>12}")
    print(f"  {'min':20} {lancedb_result['min']*1000:>10.2f}ms {lanceql_result['min']*1000:>10.2f}ms")
    print(f"  {'median':20} {lancedb_median*1000:>10.2f}ms {lanceql_median*1000:>10.2f}ms")
    print(f"  {'p95':20} {lancedb_result['p95']*1000:>10.2f}ms {lanceql_result['p95']*1000:>10.2f}ms")
    print(f"  Winner (by median): {winner} ({speedup:.2f}x faster)")


def main():
    print("=" * 70)
    print("Benchmark: Read Performance - LanceQL vs LanceDB")
    print("=" * 70)
    print(f"Warmup iterations: {WARMUP_ITERATIONS}, Timed iterations: {NUM_ITERATIONS}")

    with tempfile.TemporaryDirectory() as tmpdir:
        # Small dataset test
        print(f"\n--- Small Dataset ({ROWS_SMALL:,} rows) ---")
        data_small = create_test_data(ROWS_SMALL)
        db_path_small, lance_file_small = create_lance_file(tmpdir, data_small, "small")

        if lance_file_small:
            lancedb_small = benchmark_lancedb_read(db_path_small, WARMUP_ITERATIONS, NUM_ITERATIONS)
            lanceql_small = benchmark_lanceql_read(lance_file_small, WARMUP_ITERATIONS, NUM_ITERATIONS)
            print_comparison("Full Table Scan", lancedb_small, lanceql_small)

            # Column projection
            lancedb_col, lanceql_col = benchmark_column_projection(
                db_path_small, lance_file_small, ["id", "int_col"], WARMUP_ITERATIONS, NUM_ITERATIONS
            )
            print_comparison("Column Projection (2 cols)", lancedb_col, lanceql_col)

            # Metadata read
            lancedb_meta, lanceql_meta = benchmark_metadata_read(
                db_path_small, lance_file_small, WARMUP_ITERATIONS, NUM_ITERATIONS
            )
            print_comparison("Metadata Read", lancedb_meta, lanceql_meta)
        else:
            print("  ERROR: Could not find .lance file")

        # Medium dataset test
        print(f"\n--- Medium Dataset ({ROWS_MEDIUM:,} rows) ---")
        data_medium = create_test_data(ROWS_MEDIUM)
        db_path_medium, lance_file_medium = create_lance_file(tmpdir, data_medium, "medium")

        if lance_file_medium:
            lancedb_medium = benchmark_lancedb_read(db_path_medium, WARMUP_ITERATIONS, NUM_ITERATIONS)
            lanceql_medium = benchmark_lanceql_read(lance_file_medium, WARMUP_ITERATIONS, NUM_ITERATIONS)
            print_comparison("Full Table Scan", lancedb_medium, lanceql_medium)

            # Throughput based on median
            lancedb_throughput = ROWS_MEDIUM / lancedb_medium["median"]
            lanceql_throughput = ROWS_MEDIUM / lanceql_medium["median"]
            print(f"\n  Throughput (median):")
            print(f"    lancedb:  {lancedb_throughput/1e6:.2f}M rows/sec")
            print(f"    LanceQL:  {lanceql_throughput/1e6:.2f}M rows/sec")
        else:
            print("  ERROR: Could not find .lance file")

    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    print("""
LanceQL Reader:
  - Uses native Zig library via ctypes
  - Zero-copy Arrow C Data Interface for all column types
  - Direct memory sharing between Zig and PyArrow

lancedb:
  - Full-featured Lance library
  - Python/Rust implementation
  - Includes write support, versioning, vector search

Note: LanceQL is read-only and focused on query performance.
lancedb is the full-featured official library.
""")


if __name__ == "__main__":
    main()
