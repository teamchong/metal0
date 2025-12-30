#!/usr/bin/env python3
"""
DuckDB Python UDF Benchmark - NO PUSHDOWN

This benchmark shows the cost of using Python UDFs in DuckDB.
DuckDB must call Python for EACH ROW, resulting in ~10-50μs overhead per row.

Usage:
    python bench_duckdb_udf.py <parquet_file>
"""

import sys
import time
import duckdb
import numpy as np

if len(sys.argv) < 2:
    print("Usage: python bench_duckdb_udf.py <parquet_file>")
    sys.exit(1)

PARQUET_FILE = sys.argv[1]
WARMUP = 3
ITERATIONS = 10  # UDF is inherently slow (per-row Python calls)


def main():
    print(f"DuckDB Python UDF Benchmark (NO PUSHDOWN)")
    print(f"=" * 60)
    print(f"Input:      {PARQUET_FILE}")
    print(f"Iterations: {ITERATIONS}")
    print()

    # Connect to DuckDB
    con = duckdb.connect()

    # Create Python UDF - DuckDB calls this for EACH ROW (slow!)
    def dot_product_udf(vec_a, vec_b):
        """Row-by-row UDF - called once per row, no pushdown"""
        return float(np.dot(vec_a, vec_b))

    # Register UDF - DuckDB calls Python for EACH ROW
    # Use newer DuckDB API with string type specifications
    con.create_function(
        'dot_product',
        dot_product_udf,
        parameters=['DOUBLE[]', 'DOUBLE[]'],
        return_type='DOUBLE'
    )

    # Load data from Parquet
    print("Loading data from Parquet...")
    con.execute(f"CREATE TABLE vectors AS SELECT * FROM read_parquet('{PARQUET_FILE}')")
    num_rows = con.execute("SELECT COUNT(*) FROM vectors").fetchone()[0]
    print(f"Loaded {num_rows:,} rows")
    print()

    # Warmup
    print("Warmup...")
    for _ in range(WARMUP):
        con.execute("SELECT dot_product(vector_a, vector_b) FROM vectors LIMIT 100").fetchall()

    # Benchmark
    print("Running benchmark...")
    times = []
    for i in range(ITERATIONS):
        start = time.perf_counter_ns()

        # DuckDB calls Python UDF for EACH ROW - no pushdown!
        results = con.execute("SELECT dot_product(vector_a, vector_b) FROM vectors").fetchall()

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
    print("NOTE: DuckDB Python UDF has NO pushdown.")
    print("      Python is called for EACH ROW, causing ~10-50μs overhead per row.")
    print()

    # Output for Zig benchmark to parse
    print(f"RESULT_NS:{int(avg_ns)}")


if __name__ == "__main__":
    main()
