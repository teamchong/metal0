#!/usr/bin/env python3
"""
Benchmark: Scale Tests - LanceQL vs LanceDB
Test with large datasets: 100K, 1M, 10M rows.
Track memory usage and throughput.
"""

import time
import tempfile
import os
import sys
import gc
import tracemalloc
import numpy as np
import pyarrow as pa
import lancedb

# Add our Python package to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))
from metal0.lanceql import parquet as lanceql_pq

# Test configurations
SCALE_CONFIGS = [
    (100_000, "100K"),
    (1_000_000, "1M"),
    (10_000_000, "10M"),
]
WARMUP_ITERATIONS = 2
NUM_ITERATIONS = 5


def create_test_data(num_rows: int) -> pa.Table:
    """Create test dataset."""
    np.random.seed(42)
    return pa.table({
        "id": range(num_rows),
        "int_col": np.random.randint(0, 1000000, num_rows),
        "float_col": np.random.randn(num_rows).astype(np.float64),
        "category": [f"cat_{i % 100}" for i in range(num_rows)],
    })


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


def measure_memory(func):
    """Measure peak memory usage of a function."""
    gc.collect()
    tracemalloc.start()

    result = func()

    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    return result, peak / 1024 / 1024  # MB


def compute_stats(times: list) -> dict:
    """Compute statistics from timing results."""
    times = np.array(times)
    return {
        "min": np.min(times),
        "median": np.median(times),
        "mean": np.mean(times),
        "p95": np.percentile(times, 95),
    }


def benchmark_lancedb(db_path: str, num_rows: int) -> dict:
    """Benchmark lancedb."""
    def read_func():
        db = lancedb.connect(db_path)
        tbl = db.open_table("data")
        return tbl.to_arrow()

    # Warmup
    for _ in range(WARMUP_ITERATIONS):
        _ = read_func()

    times = []
    peak_memory = 0

    for i in range(NUM_ITERATIONS):
        gc.collect()
        start = time.perf_counter()

        if i == 0:  # Only measure memory on first iteration
            result, peak_memory = measure_memory(read_func)
        else:
            result = read_func()

        elapsed = time.perf_counter() - start
        times.append(elapsed)

    stats = compute_stats(times)
    return {
        "reader": "lancedb",
        "throughput": num_rows / stats["median"],
        "peak_memory_mb": peak_memory,
        **stats,
    }


def benchmark_lanceql(lance_file: str, num_rows: int) -> dict:
    """Benchmark LanceQL."""
    def read_func():
        return lanceql_pq.read_table(lance_file)

    # Warmup
    for _ in range(WARMUP_ITERATIONS):
        _ = read_func()

    times = []
    peak_memory = 0

    for i in range(NUM_ITERATIONS):
        gc.collect()
        start = time.perf_counter()

        if i == 0:  # Only measure memory on first iteration
            result, peak_memory = measure_memory(read_func)
        else:
            result = read_func()

        elapsed = time.perf_counter() - start
        times.append(elapsed)

    stats = compute_stats(times)
    return {
        "reader": "lanceql",
        "throughput": num_rows / stats["median"],
        "peak_memory_mb": peak_memory,
        **stats,
    }


def main():
    print("=" * 70)
    print("Benchmark: Scale Tests - LanceQL vs LanceDB")
    print("=" * 70)
    print(f"Warmup iterations: {WARMUP_ITERATIONS}, Timed iterations: {NUM_ITERATIONS}")

    results = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for num_rows, label in SCALE_CONFIGS:
            print(f"\n{'='*70}")
            print(f"Testing with {label} rows ({num_rows:,})")
            print("=" * 70)

            # Generate data
            print("  Generating test data...")
            start = time.perf_counter()
            data = create_test_data(num_rows)
            gen_time = time.perf_counter() - start
            print(f"  Generated in {gen_time:.2f}s")

            # Create Lance file
            print("  Creating Lance file...")
            start = time.perf_counter()
            db_path, lance_file = create_lance_file(tmpdir, data, f"scale_{label}")
            create_time = time.perf_counter() - start
            print(f"  Created in {create_time:.2f}s")

            if not lance_file:
                print("  ERROR: Could not create Lance file")
                continue

            # Get file size
            file_size_mb = os.path.getsize(lance_file) / 1024 / 1024
            print(f"  File size: {file_size_mb:.2f} MB")

            # Benchmark
            print("\n  Benchmarking lancedb...")
            lancedb_result = benchmark_lancedb(db_path, num_rows)

            print("  Benchmarking LanceQL...")
            lanceql_result = benchmark_lanceql(lance_file, num_rows)

            # Results
            print(f"\n  Results (after warmup):")
            print(f"  {'-'*60}")
            print(f"  {'Metric':<20} {'lancedb':>18} {'LanceQL':>18}")
            print(f"  {'-'*60}")
            print(f"  {'min':<20} {lancedb_result['min']*1000:>15.1f}ms {lanceql_result['min']*1000:>15.1f}ms")
            print(f"  {'median':<20} {lancedb_result['median']*1000:>15.1f}ms {lanceql_result['median']*1000:>15.1f}ms")
            print(f"  {'p95':<20} {lancedb_result['p95']*1000:>15.1f}ms {lanceql_result['p95']*1000:>15.1f}ms")
            print(f"  {'Throughput':<20} {lancedb_result['throughput']/1e6:>14.2f}M/s {lanceql_result['throughput']/1e6:>14.2f}M/s")
            print(f"  {'Peak Memory':<20} {lancedb_result['peak_memory_mb']:>15.1f}MB {lanceql_result['peak_memory_mb']:>15.1f}MB")
            print(f"  {'-'*60}")

            # Speedup (positive if LanceQL is faster, negative if slower)
            speedup = lancedb_result['median'] / lanceql_result['median']
            if speedup >= 1:
                print(f"\n  LanceQL is {speedup:.1f}x faster (by median)")
            else:
                print(f"\n  lancedb is {1/speedup:.1f}x faster (by median)")

            results.append({
                "rows": num_rows,
                "label": label,
                "lancedb": lancedb_result,
                "lanceql": lanceql_result,
                "speedup": speedup,
            })

            # Clean up to free memory
            del data
            gc.collect()

    # Summary
    print("\n" + "=" * 70)
    print("Summary: LanceQL Speedup vs lancedb (by median)")
    print("=" * 70)
    print(f"\n{'Rows':<15} {'Speedup':>15}")
    print("-" * 30)
    for r in results:
        print(f"{r['label']:<15} {r['speedup']:>14.1f}x")

    print("""
Implementation Notes:
- LanceQL uses zero-copy Arrow C Data Interface for all column types
- Data buffers are shared directly between Zig and PyArrow
- Only string offsets require a small conversion (4 bytes per row)

Trade-offs:
- LanceQL: Pure Zig implementation, read-only, portable
- lancedb: Full features (writes, versioning, vector search), Rust/Python
""")


if __name__ == "__main__":
    main()
