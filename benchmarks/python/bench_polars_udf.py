#!/usr/bin/env python3
"""
Polars .apply() UDF Benchmark - NO PUSHDOWN

This benchmark shows the cost of using Python UDFs in Polars.
Polars must call Python for EACH ROW via .map_elements(),
resulting in significant overhead per row.

Usage:
    python bench_polars_udf.py <parquet_file>
"""

import sys
import time
import polars as pl
import numpy as np

if len(sys.argv) < 2:
    print("Usage: python bench_polars_udf.py <parquet_file>")
    sys.exit(1)

PARQUET_FILE = sys.argv[1]
WARMUP = 3
ITERATIONS = 10  # UDF is inherently slow (per-row Python calls)


def main():
    print(f"Polars .apply() UDF Benchmark (NO PUSHDOWN)")
    print(f"=" * 60)
    print(f"Input:      {PARQUET_FILE}")
    print(f"Iterations: {ITERATIONS}")
    print()

    # Load data from Parquet
    print("Loading data from Parquet...")
    df = pl.read_parquet(PARQUET_FILE)
    num_rows = len(df)
    print(f"Loaded {num_rows:,} rows")
    print()

    # Python UDF - called for EACH ROW (slow!)
    def dot_product_udf(row: dict) -> float:
        """Row-by-row UDF - called once per row, no pushdown"""
        return float(np.dot(row['vector_a'], row['vector_b']))

    # Warmup
    print("Warmup...")
    for _ in range(WARMUP):
        _ = df.head(100).select(
            pl.struct('vector_a', 'vector_b').map_elements(dot_product_udf, return_dtype=pl.Float64)
        )

    # Benchmark
    print("Running benchmark...")
    times = []
    for i in range(ITERATIONS):
        start = time.perf_counter_ns()

        # Polars calls Python for EACH ROW via map_elements - no pushdown!
        results = df.select(
            pl.struct('vector_a', 'vector_b').map_elements(dot_product_udf, return_dtype=pl.Float64)
        )

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
    print("NOTE: Polars .map_elements() has NO pushdown.")
    print("      Python is called for EACH ROW, causing significant overhead.")
    print()

    # Output for Zig benchmark to parse
    print(f"RESULT_NS:{int(avg_ns)}")


if __name__ == "__main__":
    main()
