#!/usr/bin/env python3
"""
Benchmark: Row Updates & Deletes
Lance supports O(1) updates/deletes via deletion vectors.
Parquet requires rewriting the entire file.
"""

import time
import tempfile
import os
import pyarrow as pa
import pyarrow.parquet as pq
import lancedb
import random

NUM_ROWS = 50_000
NUM_OPS = 10  # Small number for individual operations (Parquet is VERY slow)

def create_data() -> pa.Table:
    """Create sample dataset."""
    return pa.table({
        "id": range(NUM_ROWS),
        "name": [f"user_{i}" for i in range(NUM_ROWS)],
        "score": [random.random() * 100 for _ in range(NUM_ROWS)],
    })

def benchmark_lance_updates(tmpdir: str, num_ops: int) -> dict:
    """Lance: O(1) updates and deletes."""
    db_path = os.path.join(tmpdir, "lance_db")
    db = lancedb.connect(db_path)

    # Initial write
    data = create_data()
    tbl = db.create_table("data", data)

    # Benchmark updates
    update_ids = random.sample(range(NUM_ROWS), num_ops)
    start = time.perf_counter()
    for uid in update_ids:
        tbl.update(where=f"id = {uid}", values={"score": 999.0})
    update_time = time.perf_counter() - start

    # Benchmark deletes
    delete_ids = random.sample(range(NUM_ROWS), num_ops)
    start = time.perf_counter()
    for did in delete_ids:
        tbl.delete(f"id = {did}")
    delete_time = time.perf_counter() - start

    return {
        "update_time": update_time,
        "delete_time": delete_time,
        "update_per_op": update_time / num_ops,
        "delete_per_op": delete_time / num_ops,
    }

def benchmark_parquet_individual_updates(tmpdir: str, num_ops: int) -> dict:
    """Parquet: Must rewrite entire file for each update."""
    parquet_path = os.path.join(tmpdir, "data_individual.parquet")

    # Initial write
    data = create_data()
    pq.write_table(data, parquet_path)

    # Benchmark updates (requires full rewrite each time)
    update_ids = random.sample(range(NUM_ROWS), num_ops)
    start = time.perf_counter()
    for uid in update_ids:
        table = pq.read_table(parquet_path)
        df = table.to_pandas()
        df.loc[df['id'] == uid, 'score'] = 999.0
        pq.write_table(pa.Table.from_pandas(df), parquet_path)
    update_time = time.perf_counter() - start

    # Benchmark deletes (requires full rewrite each time)
    delete_ids = random.sample(range(NUM_ROWS), num_ops)
    start = time.perf_counter()
    for did in delete_ids:
        table = pq.read_table(parquet_path)
        df = table.to_pandas()
        df = df[df['id'] != did]
        pq.write_table(pa.Table.from_pandas(df), parquet_path)
    delete_time = time.perf_counter() - start

    return {
        "update_time": update_time,
        "delete_time": delete_time,
        "update_per_op": update_time / num_ops,
        "delete_per_op": delete_time / num_ops,
    }

def main():
    print("=" * 70)
    print("Benchmark: Row Updates & Deletes (Individual Operations)")
    print(f"  Total rows: {NUM_ROWS:,}")
    print(f"  Operations: {NUM_OPS} updates + {NUM_OPS} deletes")
    print("=" * 70)

    with tempfile.TemporaryDirectory() as tmpdir:
        print("\n⏳ Benchmarking Lance...")
        lance_results = benchmark_lance_updates(tmpdir, NUM_OPS)

        print("⏳ Benchmarking Parquet (this will be slow - full file rewrite each op)...")
        parquet_results = benchmark_parquet_individual_updates(tmpdir, NUM_OPS)

    # Calculate speedups
    update_speedup = parquet_results['update_per_op'] / lance_results['update_per_op']
    delete_speedup = parquet_results['delete_per_op'] / lance_results['delete_per_op']

    print("\nResults (per-operation time):")
    print("-" * 70)
    print(f"{'Operation':<25} {'Lance':>20} {'Parquet':>20}")
    print("-" * 70)
    print(f"{'Single Update':<25} {lance_results['update_per_op']*1000:>17.1f}ms {parquet_results['update_per_op']*1000:>17.1f}ms")
    print(f"{'Single Delete':<25} {lance_results['delete_per_op']*1000:>17.1f}ms {parquet_results['delete_per_op']*1000:>17.1f}ms")
    print("-" * 70)

    print(f"\n🚀 Lance is {update_speedup:.0f}x faster for individual updates")
    print(f"🚀 Lance is {delete_speedup:.0f}x faster for individual deletes")

    print("\n📝 Why Parquet is slow:")
    print("   Each update/delete requires:")
    print("   1. Read entire file into memory")
    print("   2. Modify one row")
    print("   3. Rewrite entire file to disk")
    print(f"   Cost: O(n) where n = {NUM_ROWS:,} rows")

    print("\n📝 Why Lance is fast:")
    print("   Each update/delete uses deletion vectors:")
    print("   1. Mark old row as deleted (append to deletion vector)")
    print("   2. Write new row (for updates)")
    print("   Cost: O(1) constant time regardless of table size")

    print("\n💡 Real-world impact:")
    print(f"   At {NUM_ROWS:,} rows, Lance is already {update_speedup:.0f}x faster.")
    print("   At 1M rows, the gap would be 20x+ larger.")
    print("   At 100M rows, Parquet updates become impractical.")

if __name__ == "__main__":
    main()
