#!/usr/bin/env python3
"""
Polars → Python Batch Benchmark

This benchmark shows the "pull data then process" approach:
1. Read data from Parquet into Polars
2. Extract columns to NumPy arrays
3. Process in batch using NumPy

Usage:
    python bench_polars_batch.py <parquet_file>
"""

import sys
import time
import polars as pl
import numpy as np

if len(sys.argv) < 2:
    print("Usage: python bench_polars_batch.py <parquet_file>")
    sys.exit(1)

PARQUET_FILE = sys.argv[1]
WARMUP = 5
ITERATIONS = 20  # Batch is faster, can run more iterations


def main():
    print(f"Polars → Python Batch Benchmark")
    print(f"=" * 60)
    print(f"Input:     {PARQUET_FILE}")
    print(f"Iterations: {ITERATIONS}")
    print()

    # Load data from Parquet
    print("Loading data from Parquet...")
    df = pl.read_parquet(PARQUET_FILE)
    num_rows = len(df)
    print(f"Loaded {num_rows:,} rows")
    print()

    # Warmup
    print("Warmup...")
    for _ in range(WARMUP):
        a_arr = np.array(df.head(100)['vector_a'].to_list())
        b_arr = np.array(df.head(100)['vector_b'].to_list())
        _ = np.sum(a_arr * b_arr, axis=1)

    # Benchmark: Pull ALL data to NumPy, then batch process
    print("Running benchmark...")
    times = []
    for i in range(ITERATIONS):
        start = time.perf_counter_ns()

        # Step 1: Extract columns to Python lists
        a_list = df['vector_a'].to_list()
        b_list = df['vector_b'].to_list()

        # Step 2: Convert to NumPy arrays (data copy)
        a_arr = np.array(a_list)
        b_arr = np.array(b_list)

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
    print("NOTE: This approach requires extracting columns from Polars to NumPy.")
    print()

    # Output for Zig benchmark to parse
    print(f"RESULT_NS:{int(avg_ns)}")


if __name__ == "__main__":
    main()
