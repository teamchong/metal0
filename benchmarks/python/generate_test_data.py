#!/usr/bin/env python3
"""
Generate test Parquet file for @logic_table pushdown benchmarks.

Creates a Parquet file with vector columns for fair comparison across:
- LanceQL @logic_table (pushdown)
- DuckDB Python UDF (no pushdown)
- DuckDB batch processing
- Polars Python UDF (no pushdown)
- Polars batch processing

Usage:
    python generate_test_data.py [num_rows] [output_path]

Example:
    python generate_test_data.py 10000 /tmp/vectors.parquet
"""

import sys
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

NUM_ROWS = int(sys.argv[1]) if len(sys.argv) > 1 else 10_000
OUTPUT_PATH = sys.argv[2] if len(sys.argv) > 2 else "/tmp/logic_table_bench.parquet"
DIM = 384


def main():
    print(f"Generating test data for @logic_table benchmark")
    print(f"=" * 60)
    print(f"Rows:      {NUM_ROWS:,}")
    print(f"Dimension: {DIM}")
    print(f"Output:    {OUTPUT_PATH}")
    print()

    # Generate random vectors (deterministic seed for reproducibility)
    np.random.seed(42)

    print("Generating vectors...")
    vectors_a = [np.random.randn(DIM).astype(np.float64).tolist() for _ in range(NUM_ROWS)]
    vectors_b = [np.random.randn(DIM).astype(np.float64).tolist() for _ in range(NUM_ROWS)]

    # Create PyArrow table
    print("Creating PyArrow table...")
    table = pa.table({
        'id': pa.array(range(NUM_ROWS), type=pa.int64()),
        'vector_a': pa.array(vectors_a, type=pa.list_(pa.float64())),
        'vector_b': pa.array(vectors_b, type=pa.list_(pa.float64())),
    })

    # Write to Parquet
    print(f"Writing to {OUTPUT_PATH}...")
    pq.write_table(table, OUTPUT_PATH, compression='snappy')

    # Verify
    result = pq.read_table(OUTPUT_PATH)
    print(f"Written {len(result):,} rows to {OUTPUT_PATH}")
    print(f"File size: {__import__('os').path.getsize(OUTPUT_PATH) / 1024 / 1024:.2f} MB")
    print()
    print("Schema:")
    print(result.schema)
    print()
    print("Sample data:")
    print(result.to_pandas().head())
    print()
    print("Done!")


if __name__ == "__main__":
    main()
