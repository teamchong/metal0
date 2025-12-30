#!/usr/bin/env python3
"""Generate benchmark data files for fair comparison."""

import polars as pl
import numpy as np
import os

def generate_feature_data(rows: int, output_path: str):
    """Generate data for feature engineering benchmarks."""
    np.random.seed(42)  # Reproducible

    df = pl.DataFrame({
        "val": np.random.rand(rows) * 1000,
        "a": np.random.rand(rows) * 1000,
        "b": np.random.rand(rows) * 1000,
    })

    df.write_parquet(output_path)
    print(f"Generated {output_path}: {rows:,} rows")

def main():
    os.makedirs("/tmp/lanceql_bench", exist_ok=True)

    # Feature engineering benchmark data
    generate_feature_data(100_000, "/tmp/lanceql_bench/features_100k.parquet")
    generate_feature_data(1_000_000, "/tmp/lanceql_bench/features_1m.parquet")

    print("\nBenchmark data generated in /tmp/lanceql_bench/")

if __name__ == "__main__":
    main()
