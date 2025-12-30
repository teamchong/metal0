#!/usr/bin/env python3
"""
LanceQL @logic_table Workflow Benchmark

@logic_table approach: Python code is compiled to native Zig and runs INSIDE
the query engine, fused with data access on GPU.

This simulates what @logic_table does:
- Python decorator marks functions to be compiled
- metal0 compiles Python -> Zig -> native binary
- Query engine executes business logic alongside data access
- No Python interpreter overhead, no data serialization

For benchmarking, we call the pre-compiled Zig binary directly.
"""

import subprocess
import time
import numpy as np
import os

WARMUP = 3
ITERATIONS = 10
NUM_ROWS = 1_000_000

# Path to LanceQL CLI (built with zig build cli)
LANCEQL_CLI = "./zig-out/bin/lanceql"

def check_lanceql():
    """Check if LanceQL CLI is built"""
    if not os.path.exists(LANCEQL_CLI):
        print(f"Error: LanceQL CLI not found at {LANCEQL_CLI}")
        print("Run 'zig build cli' first")
        return False
    return True

def run_zig_benchmark(benchmark_name: str) -> float:
    """
    Run the Zig benchmark binary.

    In a real @logic_table workflow:
    1. User writes Python with @logic_table decorator
    2. metal0 compiles Python to Zig
    3. Zig is compiled to native binary
    4. Binary runs with GPU acceleration

    For this benchmark, we run the pre-compiled Zig benchmarks.
    """
    cmd = ["zig", "build", f"bench-{benchmark_name}"]

    # Run and capture output
    result = subprocess.run(cmd, capture_output=True, text=True)

    # Parse timing from output
    # The Zig benchmark outputs: "LanceQL: XX.XX ms"
    for line in result.stderr.split('\n'):
        if 'LanceQL:' in line and 'ms' in line:
            try:
                # Extract the number before "ms"
                parts = line.split()
                for i, p in enumerate(parts):
                    if p == 'ms' and i > 0:
                        return float(parts[i-1])
            except:
                pass

    return -1

def benchmark_fraud_detection():
    """
    Fraud Detection with @logic_table:

    @logic_table
    def compute_risk_score(amount, customer_age, velocity, previous_fraud, verified):
        score = 0.0
        if amount > 10000:
            score += min(0.4, amount / 125000)
        if customer_age < 30:
            score += 0.3
        if velocity > 5:
            score += min(0.2, velocity / 100)
        if previous_fraud:
            score += 0.5
        if not verified:
            score += 0.2
        return min(1.0, score)

    # This Python is compiled to native Zig and runs on GPU
    result = lanceql.query('''
        SELECT * FROM 'data.parquet'
        WHERE @compute_risk_score(amount, customer_age, velocity, previous_fraud, verified) > 0.7
    ''')

    Key benefits:
    - No Python interpreter overhead
    - Business logic runs ON the data, not after fetching
    - GPU acceleration for batch operations
    - Single pass through data (no intermediate materialization)
    """
    print("--- Workflow 1: Fraud Detection (@logic_table) ---")
    print("Python -> compiled to native Zig -> runs on GPU with query\n")

    # For now, we measure the Zig implementation directly
    # In production, @logic_table decorator would handle compilation

    # Create test data
    amounts = np.random.rand(NUM_ROWS) * 50000
    customer_ages = np.random.randint(1, 365, NUM_ROWS)
    velocities = np.random.rand(NUM_ROWS) * 20
    previous_fraud = np.random.rand(NUM_ROWS) < 0.05
    verified = np.random.rand(NUM_ROWS) > 0.2

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # This simulates what compiled @logic_table code does:
        # Vectorized operations that would run on GPU
        score = np.zeros(NUM_ROWS, dtype=np.float64)
        score += np.where(amounts > 10000, np.minimum(0.4, amounts / 125000), 0)
        score += np.where(customer_ages < 30, 0.3, 0)
        score += np.where(velocities > 5, np.minimum(0.2, velocities / 100), 0)
        score += np.where(previous_fraud, 0.5, 0)
        score += np.where(~verified, 0.2, 0)
        risk_scores = np.minimum(1.0, score)

        high_risk_count = np.sum(risk_scores > 0.7)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"@logic_table:    {avg_ms:>8.2f} ms (simulated, see zig build bench-logic-table for actual)")
    return avg_ms

def benchmark_recommendation():
    """
    Recommendation with @logic_table:

    @logic_table
    def score_product(embedding, query_embedding, in_stock, price, max_price):
        if not in_stock or price > max_price:
            return -1.0
        return cosine_similarity(embedding, query_embedding)

    # Vector search + business rules in ONE fused GPU kernel
    result = lanceql.query('''
        SELECT * FROM 'products.lance'
        WHERE @score_product(embedding, $query, in_stock, price, 500) > 0.8
        ORDER BY @score_product(...) DESC
        LIMIT 20
    ''', query=user_query_embedding)

    Key benefits:
    - Vector search runs on GPU (Metal)
    - Business rules fused into same kernel
    - No round-trip between query engine and Python
    """
    print("\n--- Workflow 2: Recommendation (@logic_table) ---")
    print("Vector search + filtering fused on GPU\n")

    # Create test data
    embeddings = np.random.randn(NUM_ROWS, 384).astype(np.float32)
    query_vec = np.random.randn(384).astype(np.float32)
    in_stock = np.random.rand(NUM_ROWS) > 0.1
    prices = np.random.rand(NUM_ROWS) * 1000

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # GPU-accelerated cosine similarity (simulated with numpy)
        # In real @logic_table, this runs on Metal GPU
        dot_products = embeddings @ query_vec
        norms = np.linalg.norm(embeddings, axis=1) * np.linalg.norm(query_vec)
        scores = dot_products / norms

        # Fused filter (would be same GPU kernel)
        scores[~in_stock] = -1
        scores[prices > 500] = -1

        # Top-k
        top_k = np.argpartition(scores, -20)[-20:]

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"@logic_table:    {avg_ms:>8.2f} ms (simulated, see zig build bench-logic-table for actual)")
    return avg_ms

def benchmark_feature_engineering():
    """
    Feature Engineering with @logic_table:

    @logic_table
    def compute_features(col_a, col_b, col_c):
        return {
            'feat_1': log(col_a),
            'feat_2': col_a / col_b,
            'feat_3': col_a * col_b + col_c,
            'feat_4': sqrt(col_a**2 + col_b**2),
            'feat_5': (col_a - col_b) / (col_a + col_b + 1)
        }

    # All transforms compiled and run in single GPU pass
    result = lanceql.query('''
        SELECT @compute_features(col_a, col_b, col_c).*
        FROM 'data.parquet'
    ''')
    """
    print("\n--- Workflow 3: Feature Engineering (@logic_table) ---")
    print("5 derived features computed in single fused pass\n")

    col_a = np.random.rand(NUM_ROWS) * 1000 + 1
    col_b = np.random.rand(NUM_ROWS) * 1000 + 1
    col_c = np.random.rand(NUM_ROWS) * 1000 + 1

    times = []

    for i in range(WARMUP + ITERATIONS):
        start = time.perf_counter()

        # Vectorized computation (simulates GPU execution)
        feat_1 = np.log(col_a)
        feat_2 = col_a / col_b
        feat_3 = col_a * col_b + col_c
        feat_4 = np.sqrt(col_a**2 + col_b**2)
        feat_5 = (col_a - col_b) / (col_a + col_b + 1)

        elapsed = (time.perf_counter() - start) * 1000

        if i >= WARMUP:
            times.append(elapsed)

    avg_ms = np.mean(times)
    print(f"@logic_table:    {avg_ms:>8.2f} ms (simulated, see zig build bench-logic-table for actual)")
    return avg_ms

if __name__ == "__main__":
    print("=" * 60)
    print("LanceQL @logic_table Workflow Benchmark")
    print("=" * 60)
    print(f"Rows: {NUM_ROWS:,}")
    print(f"Warmup: {WARMUP}, Iterations: {ITERATIONS}")
    print("\nNote: This simulates @logic_table behavior.")
    print("For actual GPU performance, run: zig build bench-logic-table\n")

    fraud_time = benchmark_fraud_detection()
    rec_time = benchmark_recommendation()
    feat_time = benchmark_feature_engineering()

    print("\n" + "=" * 60)
    print("Summary (@logic_table simulated)")
    print("=" * 60)
    print(f"Fraud Detection:     {fraud_time:>8.2f} ms")
    print(f"Recommendation:      {rec_time:>8.2f} ms")
    print(f"Feature Engineering: {feat_time:>8.2f} ms")
    print("\nFor actual native performance with GPU:")
    print("  zig build bench-logic-table")
