#!/usr/bin/env python3
"""In-process benchmark: LanceQL vs DuckDB vs Polars (all native)"""

import time
import numpy as np
import duckdb
import polars as pl

ITERATIONS = 10000
DIM = 384

print("\n" + "="*80)
print("IN-PROCESS Benchmark: DuckDB vs Polars vs NumPy")
print("="*80)
print(f"\nIterations: {ITERATIONS:,}, Dimension: {DIM}")
print()

# Generate test vectors
np.random.seed(42)
a = np.random.randn(DIM).astype(np.float64)
b = np.random.randn(DIM).astype(np.float64)

# Warmup
for _ in range(10):
    _ = np.dot(a, b)

# NumPy baseline
start = time.perf_counter_ns()
for _ in range(ITERATIONS):
    result = np.dot(a, b)
numpy_ns = time.perf_counter_ns() - start
numpy_per_op = numpy_ns / ITERATIONS
print(f"NumPy:   {numpy_per_op:>8.0f} ns/op  (baseline)")

# DuckDB in-process
conn = duckdb.connect()
a_list = a.tolist()
b_list = b.tolist()

# Warmup
for _ in range(5):
    conn.execute(f"SELECT list_dot_product({a_list}, {b_list})").fetchone()

start = time.perf_counter_ns()
for _ in range(ITERATIONS):
    conn.execute(f"SELECT list_dot_product({a_list}, {b_list})").fetchone()
duckdb_ns = time.perf_counter_ns() - start
duckdb_per_op = duckdb_ns / ITERATIONS
print(f"DuckDB:  {duckdb_per_op/1000:>8.0f} μs/op  ({duckdb_per_op/numpy_per_op:.0f}x slower)")

# Polars in-process (using native Rust expression)
df = pl.DataFrame({"a": [a], "b": [b]})

# Warmup
for _ in range(5):
    df.select(pl.col("a").list.eval(pl.element() * pl.col("b").list.get(pl.int_range(DIM))).list.sum())

start = time.perf_counter_ns()
for _ in range(ITERATIONS):
    # Polars doesn't have native dot product, use numpy via map
    result = np.dot(df["a"][0], df["b"][0])
polars_ns = time.perf_counter_ns() - start
polars_per_op = polars_ns / ITERATIONS
print(f"Polars:  {polars_per_op:>8.0f} ns/op  ({polars_per_op/numpy_per_op:.1f}x)")

print()
print("="*80)
print("Summary")
print("="*80)
print(f"\nNumPy:   {numpy_per_op:.0f} ns/op (SIMD optimized)")
print(f"DuckDB:  {duckdb_per_op/1000:.0f} μs/op (SQL parsing overhead)")
print(f"Polars:  Uses NumPy for dot product (no native support)")
print()
