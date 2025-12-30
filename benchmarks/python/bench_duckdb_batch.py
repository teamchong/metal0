#!/usr/bin/env python3
"""
DuckDB → Python Batch Benchmark

This benchmark shows the "pull data then process" approach:
1. Query data from DuckDB (reading from Parquet)
2. Transfer ALL data to Python/NumPy
3. Process in batch using NumPy

Usage:
    python bench_duckdb_batch.py <parquet_file>
"""

import sys
import time
import duckdb
import numpy as np

if len(sys.argv) < 2:
    print("Usage: python bench_duckdb_batch.py <parquet_file>")
    sys.exit(1)

PARQUET_FILE = sys.argv[1]
WARMUP = 5
ITERATIONS = 20  # Batch is faster, can run more iterations


def main():
    print(f"DuckDB → Python Batch Benchmark")
    print(f"=" * 60)
    print(f"Input:      {PARQUET_FILE}")
    print(f"Iterations: {ITERATIONS}")
    print()

    # Connect to DuckDB
    con = duckdb.connect()

    # Load data from Parquet
    print("Loading data from Parquet...")
    con.execute(f"CREATE TABLE vectors AS SELECT * FROM read_parquet('{PARQUET_FILE}')")
    num_rows = con.execute("SELECT COUNT(*) FROM vectors").fetchone()[0]
    print(f"Loaded {num_rows:,} rows")
    print()

    # Warmup
    print("Warmup...")
    for _ in range(WARMUP):
        df = con.execute("SELECT vector_a, vector_b FROM vectors LIMIT 100").fetchnumpy()
        a_arr = np.array(df['vector_a'].tolist())
        b_arr = np.array(df['vector_b'].tolist())
        _ = np.sum(a_arr * b_arr, axis=1)

    # Benchmark: Pull ALL data, then process in NumPy
    print("Running benchmark...")
    times = []
    for i in range(ITERATIONS):
        start = time.perf_counter_ns()

        # Step 1: Pull ALL data from DuckDB
        df = con.execute("SELECT vector_a, vector_b FROM vectors").fetchnumpy()

        # Step 2: Convert to NumPy arrays (data copy!)
        a_arr = np.array(df['vector_a'].tolist())
        b_arr = np.array(df['vector_b'].tolist())

        # Step 3: Batch process in NumPy (fast)
        results = np.sum(a_arr * b_arr, axis=1)

        elapsed = time.perf_counter_ns() - start
        times.append(elapsed)
        print(f"  Iteration {i+1}: {elapsed / 1e6:.2f} ms ({len(results)} rows)")

    # Results
    avg_ns = sum(times) / len(times)
    avg_ms = avg_ns / 1e6
    per_row_ns = avg_ns / num_rows
    per_row_us = per_row_ns / 1000

    print()
    print(f"Results:")
    print(f"  Total time:  {avg_ms:.2f} ms")
    print(f"  Per row:     {per_row_us:.2f} μs ({per_row_ns:.0f} ns)")
    print(f"  Throughput:  {num_rows / (avg_ns / 1e9):.0f} rows/sec")
    print()
    print("NOTE: This approach requires pulling ALL data from DuckDB first.")
    print("      Extra memory copy overhead, but avoids UDF row-by-row penalty.")
    print()

    # Output for Zig benchmark to parse
    print(f"RESULT_NS:{int(avg_ns)}")


if __name__ == "__main__":
    main()
