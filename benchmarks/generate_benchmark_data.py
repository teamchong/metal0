#!/usr/bin/env python3
"""
Generate benchmark datasets for end-to-end @logic_table comparison.

Creates identical data in Lance and Parquet formats:

1. Main table (benchmark_e2e):
   - 100K rows with embeddings (384-dim like MiniLM)
   - Columns: id, amount, customer_id, embedding

2. Customers table (for JOIN benchmarks):
   - 10K customers
   - Columns: id, name, tier

This allows fair comparison between:
- LanceQL reading Lance file (with GPU hash JOIN)
- DuckDB reading Parquet file
- Polars reading Parquet file
"""

import os
import numpy as np
import pyarrow as pa
import pyarrow.parquet as pq

try:
    import lance
    HAS_LANCE = True
except ImportError:
    HAS_LANCE = False
    print("Warning: lance not installed, will only generate Parquet")

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
NUM_ROWS = 100_000  # 100K rows for realistic benchmark
NUM_CUSTOMERS = 10_000  # 10K customers (10:1 ratio)
EMBEDDING_DIM = 384  # MiniLM dimension

def generate_orders():
    """Generate orders table with embeddings and customer_id FK."""
    np.random.seed(42)  # Reproducible

    # Generate data
    ids = np.arange(NUM_ROWS, dtype=np.int64)
    amounts = np.random.uniform(10.0, 1000.0, NUM_ROWS).astype(np.float64)
    # Foreign key to customers (0 to NUM_CUSTOMERS-1)
    customer_ids = np.random.randint(0, NUM_CUSTOMERS, NUM_ROWS).astype(np.int64)

    # Generate normalized embeddings (like real ML embeddings)
    embeddings = np.random.randn(NUM_ROWS, EMBEDDING_DIM).astype(np.float32)
    embeddings = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)

    return ids, amounts, customer_ids, embeddings


def generate_customers():
    """Generate customers table for JOIN benchmarks."""
    np.random.seed(43)  # Different seed

    ids = np.arange(NUM_CUSTOMERS, dtype=np.int64)

    # Generate realistic customer names
    first_names = ['Alice', 'Bob', 'Carol', 'David', 'Eve', 'Frank', 'Grace', 'Henry', 'Ivy', 'Jack']
    last_names = ['Smith', 'Jones', 'Brown', 'Wilson', 'Taylor', 'Davis', 'Clark', 'Hall', 'Lee', 'King']
    names = [f"{first_names[i % 10]} {last_names[(i // 10) % 10]}" for i in range(NUM_CUSTOMERS)]

    # Customer tiers: gold (10%), silver (30%), bronze (60%)
    tier_choices = np.random.choice(['gold', 'silver', 'bronze'], NUM_CUSTOMERS, p=[0.1, 0.3, 0.6])

    return ids, names, tier_choices

def save_orders_parquet(ids, amounts, customer_ids, embeddings):
    """Save orders as Parquet file."""
    embedding_list = [emb.tolist() for emb in embeddings]

    table = pa.table({
        'id': pa.array(ids, type=pa.int64()),
        'amount': pa.array(amounts, type=pa.float64()),
        'customer_id': pa.array(customer_ids, type=pa.int64()),
        'embedding': pa.array(embedding_list, type=pa.list_(pa.float32())),
    })

    path = os.path.join(OUTPUT_DIR, 'benchmark_e2e.parquet')
    pq.write_table(table, path, compression='snappy')
    print(f"Created {path}")
    print(f"  Rows: {NUM_ROWS}")
    print(f"  Size: {os.path.getsize(path) / 1024 / 1024:.1f} MB")
    return path


def save_customers_parquet(ids, names, tiers):
    """Save customers as Parquet file."""
    table = pa.table({
        'id': pa.array(ids, type=pa.int64()),
        'name': pa.array(names, type=pa.string()),
        'tier': pa.array(tiers, type=pa.string()),
    })

    path = os.path.join(OUTPUT_DIR, 'customers.parquet')
    pq.write_table(table, path, compression='snappy')
    print(f"Created {path}")
    print(f"  Rows: {NUM_CUSTOMERS}")
    print(f"  Size: {os.path.getsize(path) / 1024:.1f} KB")
    return path


def save_orders_lance(ids, amounts, customer_ids, embeddings):
    """Save orders as Lance file."""
    if not HAS_LANCE:
        print("Skipping Lance (not installed)")
        return None

    embedding_type = pa.list_(pa.float32(), EMBEDDING_DIM)
    embedding_list = [emb.tolist() for emb in embeddings]

    table = pa.table({
        'id': pa.array(ids, type=pa.int64()),
        'amount': pa.array(amounts, type=pa.float64()),
        'customer_id': pa.array(customer_ids, type=pa.int64()),
        'embedding': pa.array(embedding_list, type=embedding_type),
    })

    path = os.path.join(OUTPUT_DIR, 'benchmark_e2e.lance')
    lance.write_dataset(table, path, mode='overwrite')

    total_size = sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(path)
        for f in files
    )

    print(f"Created {path}")
    print(f"  Rows: {NUM_ROWS}")
    print(f"  Size: {total_size / 1024 / 1024:.1f} MB")
    return path


def save_customers_lance(ids, names, tiers):
    """Save customers as Lance file."""
    if not HAS_LANCE:
        print("Skipping Lance customers (not installed)")
        return None

    table = pa.table({
        'id': pa.array(ids, type=pa.int64()),
        'name': pa.array(names, type=pa.string()),
        'tier': pa.array(tiers, type=pa.string()),
    })

    path = os.path.join(OUTPUT_DIR, 'customers.lance')
    lance.write_dataset(table, path, mode='overwrite')

    total_size = sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(path)
        for f in files
    )

    print(f"Created {path}")
    print(f"  Rows: {NUM_CUSTOMERS}")
    print(f"  Size: {total_size / 1024:.1f} KB")
    return path

def verify_data():
    """Verify both formats have identical data."""
    print("\n--- Verification ---")

    # Read Parquet orders
    parquet_path = os.path.join(OUTPUT_DIR, 'benchmark_e2e.parquet')
    pq_table = pq.read_table(parquet_path)
    print(f"Orders Parquet: {len(pq_table)} rows")

    # Read Parquet customers
    customers_path = os.path.join(OUTPUT_DIR, 'customers.parquet')
    cust_table = pq.read_table(customers_path)
    print(f"Customers Parquet: {len(cust_table)} rows")

    # Read Lance
    if HAS_LANCE:
        lance_path = os.path.join(OUTPUT_DIR, 'benchmark_e2e.lance')
        lance_ds = lance.dataset(lance_path)
        print(f"Orders Lance: {lance_ds.count_rows()} rows")

        cust_lance_path = os.path.join(OUTPUT_DIR, 'customers.lance')
        cust_lance_ds = lance.dataset(cust_lance_path)
        print(f"Customers Lance: {cust_lance_ds.count_rows()} rows")

        # Verify customer_id range
        max_cust_id = pq_table['customer_id'].to_pylist()
        print(f"Customer ID range: 0 to {max(max_cust_id)} (should be < {NUM_CUSTOMERS})")


if __name__ == '__main__':
    print(f"Generating benchmark data:")
    print(f"  Orders: {NUM_ROWS} rows, {EMBEDDING_DIM}-dim embeddings")
    print(f"  Customers: {NUM_CUSTOMERS} rows (for JOIN benchmarks)")
    print()

    # Generate orders
    ids, amounts, customer_ids, embeddings = generate_orders()
    save_orders_parquet(ids, amounts, customer_ids, embeddings)
    save_orders_lance(ids, amounts, customer_ids, embeddings)
    print()

    # Generate customers
    cust_ids, names, tiers = generate_customers()
    save_customers_parquet(cust_ids, names, tiers)
    save_customers_lance(cust_ids, names, tiers)

    verify_data()
    print("\nDone!")
