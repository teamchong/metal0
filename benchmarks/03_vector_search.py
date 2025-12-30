#!/usr/bin/env python3
"""
Feature Demo: Vector Search
Lance has native ANN (Approximate Nearest Neighbor) search built-in.
Parquet has NO vector search capability - this is a Lance-only feature.

This demonstrates Lance's vector search performance.
Parquet cannot do this at all without external tools like FAISS.
"""

import time
import tempfile
import os
import numpy as np
import pyarrow as pa
import lancedb

NUM_VECTORS = 100_000
VECTOR_DIM = 384  # Common embedding dimension (e.g., MiniLM)
NUM_QUERIES = 100
TOP_K = 10

def create_data() -> tuple[pa.Table, np.ndarray]:
    """Create sample dataset with embeddings."""
    embeddings = np.random.randn(NUM_VECTORS, VECTOR_DIM).astype(np.float32)
    # Normalize for cosine similarity
    embeddings = embeddings / np.linalg.norm(embeddings, axis=1, keepdims=True)

    table = pa.table({
        "id": range(NUM_VECTORS),
        "text": [f"document_{i}" for i in range(NUM_VECTORS)],
        "embedding": [emb.tolist() for emb in embeddings],
    })
    return table, embeddings

def benchmark_lance_vector_search(tmpdir: str, data: pa.Table, queries: np.ndarray) -> dict:
    """Lance: Native vector search with IVF-PQ index."""
    db_path = os.path.join(tmpdir, "lance_db")
    db = lancedb.connect(db_path)

    # Write data
    start = time.perf_counter()
    tbl = db.create_table("vectors", data)
    write_time = time.perf_counter() - start

    # Create index on the embedding column
    start = time.perf_counter()
    tbl.create_index(
        metric="cosine",
        vector_column_name="embedding",
        num_partitions=256,
        num_sub_vectors=48,
    )
    index_time = time.perf_counter() - start

    # Search
    search_times = []
    for query in queries:
        start = time.perf_counter()
        results = tbl.search(query.tolist()).limit(TOP_K).to_list()
        search_times.append(time.perf_counter() - start)

    return {
        "write_time": write_time,
        "index_time": index_time,
        "search_time_avg": np.mean(search_times),
        "search_time_p99": np.percentile(search_times, 99),
        "qps": len(queries) / sum(search_times),
    }

def main():
    print("=" * 60)
    print("Feature Demo: Lance Native Vector Search")
    print(f"  Vectors: {NUM_VECTORS:,}")
    print(f"  Dimensions: {VECTOR_DIM}")
    print(f"  Queries: {NUM_QUERIES}")
    print(f"  Top-K: {TOP_K}")
    print("=" * 60)

    print("\n⏳ Generating random embeddings...")
    data, embeddings = create_data()
    queries = np.random.randn(NUM_QUERIES, VECTOR_DIM).astype(np.float32)
    queries = queries / np.linalg.norm(queries, axis=1, keepdims=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        print("\n⏳ Benchmarking Lance vector search...")
        results = benchmark_lance_vector_search(tmpdir, data, queries)

    print("\nLance Vector Search Results:")
    print("-" * 60)
    print(f"  Write Time:           {results['write_time']:.2f}s")
    print(f"  Index Build Time:     {results['index_time']:.2f}s")
    print(f"  Search Time (avg):    {results['search_time_avg']*1000:.2f}ms")
    print(f"  Search Time (p99):    {results['search_time_p99']*1000:.2f}ms")
    print(f"  Queries/sec:          {results['qps']:.0f}")
    print("-" * 60)

    print("\n💡 Why this matters for Parquet users:")
    print("   Parquet has NO vector search capability.")
    print("   To add vector search to Parquet, you need:")
    print("   • External library (FAISS, Annoy, ScaNN)")
    print("   • Separate index files to manage")
    print("   • Manual index rebuild on data changes")
    print("   • Complex deployment (data + index files)")
    print()
    print("   Lance provides all this built-in:")
    print("   ✅ Native ANN search in single file format")
    print("   ✅ Automatic index updates on data changes")
    print("   ✅ Combined SQL + vector search in one query")
    print("   ✅ Works with HTTP Range requests (browser/remote)")

if __name__ == "__main__":
    main()
