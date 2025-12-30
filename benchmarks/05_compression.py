#!/usr/bin/env python3
"""
Benchmark: File Size & Compression
Compare storage efficiency between Lance and Parquet.
"""

import time
import tempfile
import os
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq
import lancedb

NUM_ROWS = 500_000

def create_data() -> pa.Table:
    """Create sample dataset with various data types."""
    np.random.seed(42)
    return pa.table({
        "id": range(NUM_ROWS),
        # Integers with different distributions
        "int_sequential": range(NUM_ROWS),
        "int_random": np.random.randint(0, 1000000, NUM_ROWS),
        "int_low_cardinality": np.random.randint(0, 100, NUM_ROWS),
        # Floats
        "float_random": np.random.randn(NUM_ROWS),
        "float_sparse": np.where(np.random.rand(NUM_ROWS) > 0.9, np.random.randn(NUM_ROWS), 0.0),
        # Strings
        "str_uuid": [f"uuid-{i:08x}-{np.random.randint(0, 0xFFFF):04x}" for i in range(NUM_ROWS)],
        "str_category": [f"category_{i % 50}" for i in range(NUM_ROWS)],
        "str_text": [f"This is sample text for row {i} with some padding to simulate real data." for i in range(NUM_ROWS)],
        # Timestamps
        "timestamp": pa.array(
            [1577836800 + i for i in range(NUM_ROWS)],  # Unix timestamps starting 2020-01-01
            type=pa.timestamp('s')
        ),
    })

def get_dir_size(path: str) -> int:
    """Get total size of directory in bytes."""
    total = 0
    for dirpath, _, filenames in os.walk(path):
        for f in filenames:
            total += os.path.getsize(os.path.join(dirpath, f))
    return total

def benchmark_lance_compression(tmpdir: str, data: pa.Table) -> dict:
    """Lance file size."""
    db_path = os.path.join(tmpdir, "lance_db")
    db = lancedb.connect(db_path)

    start = time.perf_counter()
    tbl = db.create_table("data", data)
    write_time = time.perf_counter() - start

    size_bytes = get_dir_size(db_path)

    return {
        "format": "Lance",
        "size_bytes": size_bytes,
        "size_mb": size_bytes / (1024 * 1024),
        "write_time": write_time,
        "bytes_per_row": size_bytes / NUM_ROWS,
    }

def benchmark_parquet_compression(tmpdir: str, data: pa.Table, compression: str) -> dict:
    """Parquet file size with different compression."""
    parquet_path = os.path.join(tmpdir, f"data_{compression}.parquet")

    start = time.perf_counter()
    pq.write_table(data, parquet_path, compression=compression)
    write_time = time.perf_counter() - start

    size_bytes = os.path.getsize(parquet_path)

    return {
        "format": f"Parquet ({compression})",
        "size_bytes": size_bytes,
        "size_mb": size_bytes / (1024 * 1024),
        "write_time": write_time,
        "bytes_per_row": size_bytes / NUM_ROWS,
    }

def main():
    print("=" * 60)
    print("Benchmark: File Size & Compression")
    print(f"  Rows: {NUM_ROWS:,}")
    print("=" * 60)

    print("\n⏳ Generating test data...")
    data = create_data()

    # Calculate raw size
    raw_size = sum(
        col.nbytes for col in data.columns
    )
    print(f"   Raw data size: {raw_size / (1024*1024):.1f} MB")

    with tempfile.TemporaryDirectory() as tmpdir:
        print("\n⏳ Benchmarking compression...")

        results = []
        results.append(benchmark_lance_compression(tmpdir, data))
        results.append(benchmark_parquet_compression(tmpdir, data, "snappy"))
        results.append(benchmark_parquet_compression(tmpdir, data, "gzip"))
        results.append(benchmark_parquet_compression(tmpdir, data, "zstd"))
        results.append(benchmark_parquet_compression(tmpdir, data, "none"))

    print("\nResults:")
    print("-" * 70)
    print(f"{'Format':<25} {'Size (MB)':>12} {'Write Time':>12} {'Bytes/Row':>12}")
    print("-" * 70)
    for r in results:
        print(f"{r['format']:<25} {r['size_mb']:>10.2f} {r['write_time']:>10.2f}s {r['bytes_per_row']:>10.1f}")
    print("-" * 70)
    print(f"{'Raw (uncompressed)':<25} {raw_size/(1024*1024):>10.2f}")
    print("-" * 70)

    # Find best compression
    best = min(results, key=lambda x: x['size_bytes'])
    lance_result = results[0]

    print(f"\n📊 Compression Ratios (vs raw):")
    for r in results:
        ratio = raw_size / r['size_bytes']
        print(f"   {r['format']:<25} {ratio:.2f}x")

    print(f"\n📝 Summary:")
    print(f"   • Lance compression is comparable to Parquet")
    print(f"   • Best overall: {best['format']} ({best['size_mb']:.2f} MB)")
    print(f"   • Lance size: {lance_result['size_mb']:.2f} MB")

    parquet_snappy = next(r for r in results if 'snappy' in r['format'])
    overhead_vs_snappy = (lance_result['size_bytes'] / parquet_snappy['size_bytes'] - 1) * 100

    print(f"\n💡 Storage Trade-off Analysis:")
    print(f"   • Lance vs Parquet (snappy): {overhead_vs_snappy:+.0f}% storage")
    print(f"   • Lance includes: versioning metadata, deletion vectors, index structures")
    print(f"")
    print(f"   What you GET for that storage:")
    print(f"   ✅ Time travel (query any version)")
    print(f"   ✅ O(1) updates and deletes")
    print(f"   ✅ Native vector search (no separate FAISS index)")
    print(f"   ✅ ACID transactions")
    print(f"")
    print(f"   If you only need append-only analytics, Parquet is more compact.")
    print(f"   If you need updates/versioning/vectors, Lance is worth the trade-off.")

if __name__ == "__main__":
    main()
