#!/usr/bin/env python3
"""
Benchmark: LanceQL Parquet Reader vs PyArrow

Compare LanceQL's pure Zig Parquet reader against PyArrow (C++) reading
the same Parquet files with different compression settings.
"""

import time
import os
import sys
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

# Add our Python package to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))
from metal0.lanceql import parquet as lanceql_pq

ROWS = 100_000
WARMUP = 3
ITERATIONS = 10


def create_test_parquet(path: str, compression: str | None):
    """Create a Parquet file with specified compression."""
    np.random.seed(42)
    table = pa.table({
        "id": pa.array(range(ROWS), type=pa.int64()),
        "value": pa.array(np.random.randn(ROWS), type=pa.float64()),
        "name": pa.array([f"item_{i % 100}" for i in range(ROWS)]),
    })
    pq.write_table(table, path, compression=compression)
    return os.path.getsize(path)


def benchmark_pyarrow(path: str) -> dict:
    """Benchmark PyArrow reading Parquet."""
    for _ in range(WARMUP):
        _ = pq.read_table(path)

    times = []
    for _ in range(ITERATIONS):
        start = time.perf_counter()
        result = pq.read_table(path)
        times.append(time.perf_counter() - start)
        rows = len(result)

    return {
        "reader": "PyArrow (C++)",
        "min_ms": min(times) * 1000,
        "avg_ms": np.mean(times) * 1000,
        "rows": rows,
        "throughput": rows / np.mean(times) / 1e6,
    }


def benchmark_lanceql(path: str) -> dict:
    """Benchmark LanceQL reading Parquet."""
    for _ in range(WARMUP):
        _ = lanceql_pq.read_table(path)

    times = []
    for _ in range(ITERATIONS):
        start = time.perf_counter()
        result = lanceql_pq.read_table(path)
        times.append(time.perf_counter() - start)
        rows = len(result)

    return {
        "reader": "LanceQL (Zig)",
        "min_ms": min(times) * 1000,
        "avg_ms": np.mean(times) * 1000,
        "rows": rows,
        "throughput": rows / np.mean(times) / 1e6,
    }


def main():
    print("=" * 60)
    print("LanceQL Parquet Reader vs PyArrow Benchmark")
    print("=" * 60)
    print(f"Rows: {ROWS:,}, Warmup: {WARMUP}, Iterations: {ITERATIONS}\n")

    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        # Test 1: Snappy compression
        print("=" * 60)
        print("Test 1: Snappy Compression")
        print("=" * 60)

        snappy_path = os.path.join(tmpdir, "snappy.parquet")
        size = create_test_parquet(snappy_path, "snappy")
        print(f"File size: {size / 1024:.1f} KB\n")

        pyarrow_snappy = benchmark_pyarrow(snappy_path)
        lanceql_snappy = benchmark_lanceql(snappy_path)

        print(f"{'Reader':<20} {'Avg (ms)':>10} {'Throughput':>15}")
        print("-" * 45)
        print(f"{pyarrow_snappy['reader']:<20} {pyarrow_snappy['avg_ms']:>10.2f} {pyarrow_snappy['throughput']:>12.1f}M/s")
        print(f"{lanceql_snappy['reader']:<20} {lanceql_snappy['avg_ms']:>10.2f} {lanceql_snappy['throughput']:>12.1f}M/s")

        speedup_snappy = pyarrow_snappy['avg_ms'] / lanceql_snappy['avg_ms']
        print(f"\nLanceQL is {speedup_snappy:.1f}x {'faster' if speedup_snappy > 1 else 'slower'} than PyArrow\n")

        # Test 2: Uncompressed
        print("=" * 60)
        print("Test 2: Uncompressed")
        print("=" * 60)

        uncompressed_path = os.path.join(tmpdir, "uncompressed.parquet")
        size = create_test_parquet(uncompressed_path, None)
        print(f"File size: {size / 1024:.1f} KB\n")

        pyarrow_uncomp = benchmark_pyarrow(uncompressed_path)
        lanceql_uncomp = benchmark_lanceql(uncompressed_path)

        print(f"{'Reader':<20} {'Avg (ms)':>10} {'Throughput':>15}")
        print("-" * 45)
        print(f"{pyarrow_uncomp['reader']:<20} {pyarrow_uncomp['avg_ms']:>10.2f} {pyarrow_uncomp['throughput']:>12.1f}M/s")
        print(f"{lanceql_uncomp['reader']:<20} {lanceql_uncomp['avg_ms']:>10.2f} {lanceql_uncomp['throughput']:>12.1f}M/s")

        speedup_uncomp = pyarrow_uncomp['avg_ms'] / lanceql_uncomp['avg_ms']
        print(f"\nLanceQL is {speedup_uncomp:.1f}x {'faster' if speedup_uncomp > 1 else 'slower'} than PyArrow\n")

        # Summary for README
        print("=" * 60)
        print("README Table (copy-paste):")
        print("=" * 60)
        print("""
| Test | Dataset | PyArrow (C++) | LanceQL (Zig) | Speedup |
|------|---------|---------------|---------------|---------|""")
        print(f"| Snappy Compressed | {ROWS//1000}K rows | {pyarrow_snappy['throughput']:.1f}M rows/s | {lanceql_snappy['throughput']:.1f}M rows/s | **{speedup_snappy:.1f}x faster** |")
        print(f"| Uncompressed | {ROWS//1000}K rows | {pyarrow_uncomp['throughput']:.1f}M rows/s | {lanceql_uncomp['throughput']:.1f}M rows/s | **{speedup_uncomp:.1f}x faster** |")


if __name__ == "__main__":
    main()
