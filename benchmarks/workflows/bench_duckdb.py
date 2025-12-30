#!/usr/bin/env python3
"""
DuckDB Workflow Benchmark

Traditional approach: SQL query to fetch data, then Python processes results.
This is how DuckDB users typically work - query returns data, app logic in Python.
"""

import time
import duckdb
import numpy as np

WARMUP = 3
ITERATIONS = 10
NUM_ROWS = 1_000_000

def create_test_data():
    """Create test parquet file with DuckDB"""
    print("Creating test data...")
    duckdb.sql(f"""
        COPY (
            SELECT
                i AS id,
                random() * 50000 AS amount,
                (random() * 365)::INTEGER AS customer_age,
                random() * 20 AS velocity,
                random() < 0.05 AS previous_fraud,
                random() > 0.2 AS verified,
                random() * 1000 AS price,
                random() > 0.1 AS in_stock,
                random() * 1000 + 1 AS col_a,
                random() * 1000 + 1 AS col_b,
                random() * 1000 + 1 AS col_c
            FROM range({NUM_ROWS}) t(i)
        ) TO '/tmp/bench_workflow.parquet' (FORMAT PARQUET);
    """)

    # Create embeddings file (384-dim vectors)
    print("Creating embeddings...")
    embeddings = np.random.randn(NUM_ROWS, 384).astype(np.float32)
    np.save('/tmp/bench_embeddings.npy', embeddings)
    print("Test data created.\n")

def benchmark_fraud_detection():
    """
    Fraud Detection Workflow:
    1. DuckDB: Fetch 5 columns
    2. Python: Compute risk_score for each row
    3. Python: Filter high-risk rows
    """
    print("--- Workflow 1: Fraud Detection ---")
    print("DuckDB fetches data, Python computes risk scores\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: DuckDB fetches data
        df = duckdb.sql("""
            SELECT amount, customer_age, velocity, previous_fraud, verified
            FROM '/tmp/bench_workflow.parquet'
        """).fetchnumpy()

        # Step 2: Python computes risk score (row by row, like typical app code)
        n = len(df['amount'])
        risk_scores = np.zeros(n)

        for j in range(n):
            score = 0.0
            if df['amount'][j] > 10000:
                score += min(0.4, df['amount'][j] / 125000)
            if df['customer_age'][j] < 30:
                score += 0.3
            if df['velocity'][j] > 5:
                score += min(0.2, df['velocity'][j] / 100)
            if df['previous_fraud'][j]:
                score += 0.5
            if not df['verified'][j]:
                score += 0.2
            risk_scores[j] = min(1.0, score)

        # Step 3: Filter high-risk
        high_risk_count = np.sum(risk_scores > 0.7)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"DuckDB + Python: {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_fraud_detection_vectorized():
    """Same but with vectorized numpy (best case for Python)"""
    print("\n--- Workflow 1b: Fraud Detection (Vectorized) ---")
    print("DuckDB fetches data, NumPy vectorized computation\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: DuckDB fetches data
        df = duckdb.sql("""
            SELECT amount, customer_age, velocity, previous_fraud, verified
            FROM '/tmp/bench_workflow.parquet'
        """).fetchnumpy()

        # Step 2: Vectorized numpy computation
        score = np.zeros(len(df['amount']))
        score += np.where(df['amount'] > 10000, np.minimum(0.4, df['amount'] / 125000), 0)
        score += np.where(df['customer_age'] < 30, 0.3, 0)
        score += np.where(df['velocity'] > 5, np.minimum(0.2, df['velocity'] / 100), 0)
        score += np.where(df['previous_fraud'], 0.5, 0)
        score += np.where(~df['verified'], 0.2, 0)
        risk_scores = np.minimum(1.0, score)

        # Step 3: Filter
        high_risk_count = np.sum(risk_scores > 0.7)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"DuckDB + NumPy:  {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_recommendation():
    """
    Recommendation Workflow:
    1. DuckDB: Fetch filtered rows (in_stock, price < 500)
    2. Python: Load embeddings, compute cosine similarity
    3. Python: Find top-k results
    """
    print("\n--- Workflow 2: Recommendation ---")
    print("DuckDB fetches filtered data, Python does vector search\n")

    # Load embeddings
    embeddings = np.load('/tmp/bench_embeddings.npy')
    query_vec = np.random.randn(384).astype(np.float32)

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: DuckDB fetches filtered data
        result = duckdb.sql("""
            SELECT id, price
            FROM '/tmp/bench_workflow.parquet'
            WHERE in_stock = true AND price < 500
        """).fetchnumpy()

        ids = result['id']

        # Step 2: Python computes cosine similarity for filtered rows
        filtered_embeddings = embeddings[ids]

        # Cosine similarity
        dot_products = filtered_embeddings @ query_vec
        norms = np.linalg.norm(filtered_embeddings, axis=1) * np.linalg.norm(query_vec)
        scores = dot_products / norms

        # Step 3: Top-k
        top_k_indices = np.argpartition(scores, -20)[-20:]

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"DuckDB + Python: {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_feature_engineering():
    """
    Feature Engineering Workflow:
    1. DuckDB: Fetch raw columns
    2. Python: Compute 5 derived features
    """
    print("\n--- Workflow 3: Feature Engineering ---")
    print("DuckDB fetches data, Python computes derived features\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: DuckDB fetches data
        df = duckdb.sql("""
            SELECT col_a, col_b, col_c
            FROM '/tmp/bench_workflow.parquet'
        """).fetchnumpy()

        # Step 2: Python computes features (vectorized)
        feat_1 = np.log(df['col_a'])
        feat_2 = df['col_a'] / df['col_b']
        feat_3 = df['col_a'] * df['col_b'] + df['col_c']
        feat_4 = np.sqrt(df['col_a']**2 + df['col_b']**2)
        feat_5 = (df['col_a'] - df['col_b']) / (df['col_a'] + df['col_b'] + 1)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"DuckDB + NumPy:  {avg_ms:>8.2f} ms")
    return avg_ms

if __name__ == "__main__":
    print("=" * 60)
    print("DuckDB Workflow Benchmark")
    print("=" * 60)
    print(f"Rows: {NUM_ROWS:,}")
    print(f"Warmup: {WARMUP}, Iterations: {ITERATIONS}\n")

    create_test_data()

    fraud_time = benchmark_fraud_detection()
    fraud_vec_time = benchmark_fraud_detection_vectorized()
    rec_time = benchmark_recommendation()
    feat_time = benchmark_feature_engineering()

    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Fraud Detection (loop):      {fraud_time:>8.2f} ms")
    print(f"Fraud Detection (vectorized):{fraud_vec_time:>8.2f} ms")
    print(f"Recommendation:              {rec_time:>8.2f} ms")
    print(f"Feature Engineering:         {feat_time:>8.2f} ms")
