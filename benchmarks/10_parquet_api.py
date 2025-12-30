#!/usr/bin/env python3
"""
Benchmark: PyArrow Parquet Drop-in Replacement API

Compare LanceQL's pyarrow.parquet-compatible API against:
1. pyarrow.parquet reading Parquet files
2. lancedb reading Lance files

This tests the drop-in replacement use case:
    # Before:
    import pyarrow.parquet as pq
    table = pq.read_table('data.parquet')

    # After:
    from metal0.lanceql import parquet as pq
    table = pq.read_table('data.lance')
"""

import time
import tempfile
import os
import sys
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq_arrow
import lancedb

# Add our Python package to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))
from metal0.lanceql import parquet as pq_lance

# Test configurations
ROWS_SMALL = 100_000
ROWS_MEDIUM = 1_000_000
WARMUP_ITERATIONS = 3
NUM_ITERATIONS = 10


def create_test_data(num_rows: int) -> pa.Table:
    """Create test dataset with various column types."""
    np.random.seed(42)
    return pa.table({
        "id": pa.array(range(num_rows), type=pa.int64()),
        "int_col": pa.array(np.random.randint(0, 1000000, num_rows), type=pa.int64()),
        "float_col": pa.array(np.random.randn(num_rows), type=pa.float64()),
        "str_col": pa.array([f"value_{i % 1000}" for i in range(num_rows)]),
    })


def create_parquet_file(tmpdir: str, data: pa.Table, name: str) -> str:
    """Create a Parquet file."""
    path = os.path.join(tmpdir, f"{name}.parquet")
    pq_arrow.write_table(data, path)
    return path


def create_lance_file(tmpdir: str, data: pa.Table, name: str) -> tuple:
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


def benchmark_pyarrow_parquet(parquet_file: str, warmup: int, iterations: int) -> dict:
    """Benchmark pyarrow.parquet.read_table()."""
    # Warmup
    for _ in range(warmup):
        _ = pq_arrow.read_table(parquet_file)

    # Timed runs
    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = pq_arrow.read_table(parquet_file)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        row_count = len(result)

    stats = compute_stats(times)
    return {"reader": "pyarrow.parquet", "row_count": row_count, **stats}


def benchmark_lanceql_parquet_api(lance_file: str, warmup: int, iterations: int) -> dict:
    """Benchmark lanceql.parquet.read_table() - our drop-in replacement."""
    # Warmup
    for _ in range(warmup):
        _ = pq_lance.read_table(lance_file)

    # Timed runs
    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = pq_lance.read_table(lance_file)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        row_count = len(result)

    stats = compute_stats(times)
    return {"reader": "lanceql.parquet", "row_count": row_count, **stats}


def benchmark_lancedb(db_path: str, warmup: int, iterations: int) -> dict:
    """Benchmark lancedb.open_table().to_arrow()."""
    # Warmup
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
    return {"reader": "lancedb", "row_count": row_count, **stats}


def benchmark_parquetfile_api(parquet_file: str, lance_file: str, warmup: int, iterations: int) -> tuple:
    """Benchmark ParquetFile API (more control over reading)."""
    # pyarrow ParquetFile
    for _ in range(warmup):
        with pq_arrow.ParquetFile(parquet_file) as pf:
            _ = pf.read()

    pyarrow_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        with pq_arrow.ParquetFile(parquet_file) as pf:
            result = pf.read()
        pyarrow_times.append(time.perf_counter() - start)

    # lanceql ParquetFile (drop-in replacement)
    for _ in range(warmup):
        with pq_lance.ParquetFile(lance_file) as pf:
            _ = pf.read()

    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        with pq_lance.ParquetFile(lance_file) as pf:
            result = pf.read()
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "pyarrow.ParquetFile", **compute_stats(pyarrow_times)},
        {"reader": "lanceql.ParquetFile", **compute_stats(lanceql_times)},
    )


def benchmark_column_selection(parquet_file: str, lance_file: str, columns: list, warmup: int, iterations: int) -> tuple:
    """Benchmark column selection (projection pushdown)."""
    # pyarrow
    for _ in range(warmup):
        _ = pq_arrow.read_table(parquet_file, columns=columns)

    pyarrow_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = pq_arrow.read_table(parquet_file, columns=columns)
        pyarrow_times.append(time.perf_counter() - start)

    # lanceql
    for _ in range(warmup):
        _ = pq_lance.read_table(lance_file, columns=columns)

    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        result = pq_lance.read_table(lance_file, columns=columns)
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "pyarrow.parquet", **compute_stats(pyarrow_times)},
        {"reader": "lanceql.parquet", **compute_stats(lanceql_times)},
    )


def benchmark_metadata(parquet_file: str, lance_file: str, warmup: int, iterations: int) -> tuple:
    """Benchmark metadata reading (schema, row count)."""
    # pyarrow
    for _ in range(warmup):
        _ = pq_arrow.read_metadata(parquet_file)

    pyarrow_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        meta = pq_arrow.read_metadata(parquet_file)
        _ = meta.num_rows
        _ = meta.num_columns
        pyarrow_times.append(time.perf_counter() - start)

    # lanceql
    for _ in range(warmup):
        _ = pq_lance.read_metadata(lance_file)

    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        meta = pq_lance.read_metadata(lance_file)
        _ = meta.num_rows
        _ = meta.num_columns
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "pyarrow.parquet", **compute_stats(pyarrow_times)},
        {"reader": "lanceql.parquet", **compute_stats(lanceql_times)},
    )


def benchmark_iter_batches(parquet_file: str, lance_file: str, batch_size: int, warmup: int, iterations: int) -> tuple:
    """Benchmark iter_batches() for streaming reads."""
    # pyarrow
    for _ in range(warmup):
        with pq_arrow.ParquetFile(parquet_file) as pf:
            for batch in pf.iter_batches(batch_size=batch_size):
                pass

    pyarrow_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        with pq_arrow.ParquetFile(parquet_file) as pf:
            for batch in pf.iter_batches(batch_size=batch_size):
                pass
        pyarrow_times.append(time.perf_counter() - start)

    # lanceql
    for _ in range(warmup):
        with pq_lance.ParquetFile(lance_file) as pf:
            for batch in pf.iter_batches(batch_size=batch_size):
                pass

    lanceql_times = []
    for _ in range(iterations):
        start = time.perf_counter()
        with pq_lance.ParquetFile(lance_file) as pf:
            for batch in pf.iter_batches(batch_size=batch_size):
                pass
        lanceql_times.append(time.perf_counter() - start)

    return (
        {"reader": "pyarrow.ParquetFile", **compute_stats(pyarrow_times)},
        {"reader": "lanceql.ParquetFile", **compute_stats(lanceql_times)},
    )


def print_comparison(test_name: str, results: list):
    """Print comparison results."""
    print(f"\n{test_name}:")
    print(f"  {'Reader':<25} {'min':>10} {'median':>10} {'p95':>10}")
    print(f"  {'-'*55}")

    for r in results:
        print(f"  {r['reader']:<25} {r['min']*1000:>8.2f}ms {r['median']*1000:>8.2f}ms {r['p95']*1000:>8.2f}ms")

    # Find fastest by median
    sorted_results = sorted(results, key=lambda x: x['median'])
    fastest = sorted_results[0]
    for r in sorted_results[1:]:
        speedup = r['median'] / fastest['median']
        print(f"  {fastest['reader']} is {speedup:.1f}x faster than {r['reader']}")


def main():
    print("=" * 70)
    print("Benchmark: PyArrow Parquet Drop-in Replacement API")
    print("=" * 70)
    print(f"Warmup: {WARMUP_ITERATIONS}, Iterations: {NUM_ITERATIONS}")
    print()
    print("Comparing:")
    print("  1. pyarrow.parquet (reading .parquet files)")
    print("  2. lanceql.parquet (reading .lance files) - our drop-in replacement")
    print("  3. lancedb (reading .lance files) - official Lance library")

    with tempfile.TemporaryDirectory() as tmpdir:
        # ============================================================
        # Small Dataset (100K rows)
        # ============================================================
        print(f"\n{'='*70}")
        print(f"Small Dataset ({ROWS_SMALL:,} rows)")
        print("=" * 70)

        data = create_test_data(ROWS_SMALL)
        parquet_file = create_parquet_file(tmpdir, data, "small")
        db_path, lance_file = create_lance_file(tmpdir, data, "small")

        parquet_size = os.path.getsize(parquet_file) / 1024 / 1024
        lance_size = os.path.getsize(lance_file) / 1024 / 1024
        print(f"  Parquet file: {parquet_size:.2f} MB")
        print(f"  Lance file: {lance_size:.2f} MB")

        # read_table() comparison
        pyarrow_result = benchmark_pyarrow_parquet(parquet_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        lanceql_result = benchmark_lanceql_parquet_api(lance_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        lancedb_result = benchmark_lancedb(db_path, WARMUP_ITERATIONS, NUM_ITERATIONS)
        print_comparison("read_table() - Full Table Scan", [pyarrow_result, lanceql_result, lancedb_result])

        # ParquetFile API
        pyarrow_pf, lanceql_pf = benchmark_parquetfile_api(parquet_file, lance_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        print_comparison("ParquetFile.read()", [pyarrow_pf, lanceql_pf])

        # Column selection
        pyarrow_col, lanceql_col = benchmark_column_selection(
            parquet_file, lance_file, ["id", "float_col"], WARMUP_ITERATIONS, NUM_ITERATIONS
        )
        print_comparison("read_table(columns=['id', 'float_col'])", [pyarrow_col, lanceql_col])

        # Metadata
        pyarrow_meta, lanceql_meta = benchmark_metadata(parquet_file, lance_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        print_comparison("read_metadata()", [pyarrow_meta, lanceql_meta])

        # iter_batches
        pyarrow_iter, lanceql_iter = benchmark_iter_batches(
            parquet_file, lance_file, 10000, WARMUP_ITERATIONS, NUM_ITERATIONS
        )
        print_comparison("iter_batches(batch_size=10000)", [pyarrow_iter, lanceql_iter])

        # ============================================================
        # Medium Dataset (1M rows)
        # ============================================================
        print(f"\n{'='*70}")
        print(f"Medium Dataset ({ROWS_MEDIUM:,} rows)")
        print("=" * 70)

        data = create_test_data(ROWS_MEDIUM)
        parquet_file = create_parquet_file(tmpdir, data, "medium")
        db_path, lance_file = create_lance_file(tmpdir, data, "medium")

        parquet_size = os.path.getsize(parquet_file) / 1024 / 1024
        lance_size = os.path.getsize(lance_file) / 1024 / 1024
        print(f"  Parquet file: {parquet_size:.2f} MB")
        print(f"  Lance file: {lance_size:.2f} MB")

        # read_table() comparison
        pyarrow_result = benchmark_pyarrow_parquet(parquet_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        lanceql_result = benchmark_lanceql_parquet_api(lance_file, WARMUP_ITERATIONS, NUM_ITERATIONS)
        lancedb_result = benchmark_lancedb(db_path, WARMUP_ITERATIONS, NUM_ITERATIONS)
        print_comparison("read_table() - Full Table Scan", [pyarrow_result, lanceql_result, lancedb_result])

        # Throughput
        print(f"\n  Throughput (by median):")
        print(f"    pyarrow.parquet: {ROWS_MEDIUM / pyarrow_result['median'] / 1e6:.2f}M rows/sec")
        print(f"    lanceql.parquet: {ROWS_MEDIUM / lanceql_result['median'] / 1e6:.2f}M rows/sec")
        print(f"    lancedb:         {ROWS_MEDIUM / lancedb_result['median'] / 1e6:.2f}M rows/sec")

    # Summary
    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)
    print("""
Drop-in Replacement Usage:
    # Before (reading Parquet):
    import pyarrow.parquet as pq
    table = pq.read_table('data.parquet')

    # After (reading Lance):
    from metal0.lanceql import parquet as pq
    table = pq.read_table('data.lance')

Supported APIs:
    - read_table(source, columns=None)
    - read_metadata(source)
    - read_schema(source)
    - ParquetFile(source)
        - .read(columns=None)
        - .schema
        - .metadata
        - .iter_batches(batch_size)
        - .num_row_groups

Note: LanceQL uses zero-copy Arrow C Data Interface for maximum performance.
""")


if __name__ == "__main__":
    main()
