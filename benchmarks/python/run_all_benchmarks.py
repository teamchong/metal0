#!/usr/bin/env python3
"""
Master Benchmark Script: @logic_table Pushdown Comparison

Runs ALL benchmarks and compares:
1. LanceQL @logic_table (native pushdown)
2. DuckDB Python UDF (no pushdown)
3. DuckDB → Python batch
4. Polars Python UDF (no pushdown)
5. Polars → Python batch

Usage:
    python run_all_benchmarks.py [num_rows]

Example:
    python run_all_benchmarks.py 10000
"""

import os
import sys
import subprocess
import time

NUM_ROWS = int(sys.argv[1]) if len(sys.argv) > 1 else 50_000  # Target ~5s per benchmark
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PARQUET_FILE = f"/tmp/logic_table_bench_{NUM_ROWS}.parquet"


def run_script(name: str, script: str, args: list = None) -> dict:
    """Run a benchmark script and parse results."""
    args = args or []
    cmd = ["python3", os.path.join(SCRIPT_DIR, script)] + args

    print(f"\n{'=' * 70}")
    print(f"Running: {name}")
    print(f"{'=' * 70}\n")

    start = time.time()
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - start

    print(result.stdout)
    if result.stderr:
        print(f"STDERR: {result.stderr}")

    # Parse result
    result_ns = None
    for line in result.stdout.split('\n'):
        if line.startswith('RESULT_NS:'):
            result_ns = int(line.split(':')[1])

    return {
        'name': name,
        'elapsed': elapsed,
        'result_ns': result_ns,
        'success': result.returncode == 0 and result_ns is not None
    }


def main():
    print(f"=" * 70)
    print(f"@logic_table Pushdown Benchmark")
    print(f"=" * 70)
    print(f"Rows:    {NUM_ROWS:,}")
    print(f"Parquet: {PARQUET_FILE}")
    print()

    # Step 1: Generate test data
    print("Step 1: Generating test Parquet file...")
    result = subprocess.run([
        "python3",
        os.path.join(SCRIPT_DIR, "generate_test_data.py"),
        str(NUM_ROWS),
        PARQUET_FILE
    ], capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print(f"ERROR: {result.stderr}")
        sys.exit(1)

    # Step 2: Run all benchmarks
    results = []

    # DuckDB UDF (no pushdown)
    r = run_script("DuckDB Python UDF", "bench_duckdb_udf.py", [PARQUET_FILE])
    results.append(r)

    # DuckDB batch
    r = run_script("DuckDB → Python Batch", "bench_duckdb_batch.py", [PARQUET_FILE])
    results.append(r)

    # Polars UDF (no pushdown)
    r = run_script("Polars Python UDF", "bench_polars_udf.py", [PARQUET_FILE])
    results.append(r)

    # Polars batch
    r = run_script("Polars → Python Batch", "bench_polars_batch.py", [PARQUET_FILE])
    results.append(r)

    # Step 3: Summary
    print(f"\n{'=' * 70}")
    print(f"SUMMARY: {NUM_ROWS:,} rows × 384 dimensions")
    print(f"{'=' * 70}\n")

    print(f"{'Method':<30} {'Total (ms)':>15} {'Per Row (ns)':>15} {'Status':<10}")
    print(f"{'-' * 30} {'-' * 15} {'-' * 15} {'-' * 10}")

    for r in results:
        if r['success']:
            total_ms = r['result_ns'] / 1e6
            per_row_ns = r['result_ns'] / NUM_ROWS
            print(f"{r['name']:<30} {total_ms:>15.2f} {per_row_ns:>15.0f} {'✓':<10}")
        else:
            print(f"{r['name']:<30} {'N/A':>15} {'N/A':>15} {'✗ FAILED':<10}")

    print()
    print("NOTE: LanceQL @logic_table benchmark runs via Zig:")
    print("      zig build bench-logic-table")
    print()
    print("Compare the Python results above with LanceQL native performance.")
    print()


if __name__ == "__main__":
    main()
