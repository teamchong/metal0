#!/usr/bin/env python3
"""
Polars Workflow Benchmark

Traditional approach: Polars query to fetch data, then Python processes results.
This is how Polars users typically work - query returns data, app logic in Python.
"""

import time
import polars as pl
import numpy as np

WARMUP = 3
ITERATIONS = 10
NUM_ROWS = 1_000_000

def benchmark_fraud_detection():
    """
    Fraud Detection Workflow:
    1. Polars: Fetch 5 columns
    2. Python: Compute risk_score for each row
    3. Python: Filter high-risk rows
    """
    print("--- Workflow 1: Fraud Detection ---")
    print("Polars fetches data, Python computes risk scores\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: Polars fetches data
        df = pl.read_parquet(
            '/tmp/bench_workflow.parquet',
            columns=['amount', 'customer_age', 'velocity', 'previous_fraud', 'verified']
        )

        # Convert to numpy for Python processing
        amount = df['amount'].to_numpy()
        customer_age = df['customer_age'].to_numpy()
        velocity = df['velocity'].to_numpy()
        previous_fraud = df['previous_fraud'].to_numpy()
        verified = df['verified'].to_numpy()

        # Step 2: Python computes risk score (row by row)
        n = len(amount)
        risk_scores = np.zeros(n)

        for j in range(n):
            score = 0.0
            if amount[j] > 10000:
                score += min(0.4, amount[j] / 125000)
            if customer_age[j] < 30:
                score += 0.3
            if velocity[j] > 5:
                score += min(0.2, velocity[j] / 100)
            if previous_fraud[j]:
                score += 0.5
            if not verified[j]:
                score += 0.2
            risk_scores[j] = min(1.0, score)

        # Step 3: Filter high-risk
        high_risk_count = np.sum(risk_scores > 0.7)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"Polars + Python: {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_fraud_detection_vectorized():
    """Same but with vectorized numpy (best case for Python)"""
    print("\n--- Workflow 1b: Fraud Detection (Vectorized) ---")
    print("Polars fetches data, NumPy vectorized computation\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: Polars fetches data
        df = pl.read_parquet(
            '/tmp/bench_workflow.parquet',
            columns=['amount', 'customer_age', 'velocity', 'previous_fraud', 'verified']
        )

        amount = df['amount'].to_numpy()
        customer_age = df['customer_age'].to_numpy()
        velocity = df['velocity'].to_numpy()
        previous_fraud = df['previous_fraud'].to_numpy()
        verified = df['verified'].to_numpy()

        # Step 2: Vectorized numpy computation
        score = np.zeros(len(amount))
        score += np.where(amount > 10000, np.minimum(0.4, amount / 125000), 0)
        score += np.where(customer_age < 30, 0.3, 0)
        score += np.where(velocity > 5, np.minimum(0.2, velocity / 100), 0)
        score += np.where(previous_fraud, 0.5, 0)
        score += np.where(~verified, 0.2, 0)
        risk_scores = np.minimum(1.0, score)

        # Step 3: Filter
        high_risk_count = np.sum(risk_scores > 0.7)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"Polars + NumPy:  {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_fraud_polars_native():
    """Use Polars expressions instead of Python loops"""
    print("\n--- Workflow 1c: Fraud Detection (Polars Native) ---")
    print("Polars does all computation with expressions\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # All computation in Polars expressions
        result = pl.read_parquet('/tmp/bench_workflow.parquet').select([
            pl.lit(0.0)
            .add(pl.when(pl.col('amount') > 10000)
                 .then(pl.min_horizontal(pl.lit(0.4), pl.col('amount') / 125000))
                 .otherwise(0))
            .add(pl.when(pl.col('customer_age') < 30).then(0.3).otherwise(0))
            .add(pl.when(pl.col('velocity') > 5)
                 .then(pl.min_horizontal(pl.lit(0.2), pl.col('velocity') / 100))
                 .otherwise(0))
            .add(pl.when(pl.col('previous_fraud')).then(0.5).otherwise(0))
            .add(pl.when(~pl.col('verified')).then(0.2).otherwise(0))
            .clip(0, 1)
            .alias('risk_score')
        ]).filter(pl.col('risk_score') > 0.7)

        high_risk_count = len(result)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"Polars Native:   {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_recommendation():
    """
    Recommendation Workflow:
    1. Polars: Fetch filtered rows
    2. Python: Load embeddings, compute cosine similarity
    3. Python: Find top-k results
    """
    print("\n--- Workflow 2: Recommendation ---")
    print("Polars fetches filtered data, Python does vector search\n")

    # Load embeddings
    embeddings = np.load('/tmp/bench_embeddings.npy')
    query_vec = np.random.randn(384).astype(np.float32)

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: Polars fetches filtered data
        df = pl.read_parquet('/tmp/bench_workflow.parquet').filter(
            (pl.col('in_stock') == True) & (pl.col('price') < 500)
        ).select(['id', 'price'])

        ids = df['id'].to_numpy()

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
    print(f"Polars + Python: {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_feature_engineering():
    """
    Feature Engineering Workflow:
    1. Polars: Fetch raw columns
    2. Python: Compute 5 derived features
    """
    print("\n--- Workflow 3: Feature Engineering ---")
    print("Polars fetches data, Python computes derived features\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Step 1: Polars fetches data
        df = pl.read_parquet(
            '/tmp/bench_workflow.parquet',
            columns=['col_a', 'col_b', 'col_c']
        )

        col_a = df['col_a'].to_numpy()
        col_b = df['col_b'].to_numpy()
        col_c = df['col_c'].to_numpy()

        # Step 2: Python computes features (vectorized)
        feat_1 = np.log(col_a)
        feat_2 = col_a / col_b
        feat_3 = col_a * col_b + col_c
        feat_4 = np.sqrt(col_a**2 + col_b**2)
        feat_5 = (col_a - col_b) / (col_a + col_b + 1)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"Polars + NumPy:  {avg_ms:>8.2f} ms")
    return avg_ms

def benchmark_feature_polars_native():
    """Use Polars expressions"""
    print("\n--- Workflow 3b: Feature Engineering (Polars Native) ---")
    print("Polars does all computation with expressions\n")

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        result = pl.read_parquet('/tmp/bench_workflow.parquet').select([
            pl.col('col_a').log().alias('feat_1'),
            (pl.col('col_a') / pl.col('col_b')).alias('feat_2'),
            (pl.col('col_a') * pl.col('col_b') + pl.col('col_c')).alias('feat_3'),
            (pl.col('col_a').pow(2) + pl.col('col_b').pow(2)).sqrt().alias('feat_4'),
            ((pl.col('col_a') - pl.col('col_b')) / (pl.col('col_a') + pl.col('col_b') + 1)).alias('feat_5'),
        ])

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"Polars Native:   {avg_ms:>8.2f} ms")
    return avg_ms

if __name__ == "__main__":
    print("=" * 60)
    print("Polars Workflow Benchmark")
    print("=" * 60)
    print(f"Rows: {NUM_ROWS:,}")
    print(f"Warmup: {WARMUP}, Iterations: {ITERATIONS}\n")

    fraud_time = benchmark_fraud_detection()
    fraud_vec_time = benchmark_fraud_detection_vectorized()
    fraud_native_time = benchmark_fraud_polars_native()
    rec_time = benchmark_recommendation()
    feat_time = benchmark_feature_engineering()
    feat_native_time = benchmark_feature_polars_native()

    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"Fraud Detection (loop):      {fraud_time:>8.2f} ms")
    print(f"Fraud Detection (vectorized):{fraud_vec_time:>8.2f} ms")
    print(f"Fraud Detection (native):    {fraud_native_time:>8.2f} ms")
    print(f"Recommendation:              {rec_time:>8.2f} ms")
    print(f"Feature Engineering (numpy): {feat_time:>8.2f} ms")
    print(f"Feature Engineering (native):{feat_native_time:>8.2f} ms")
