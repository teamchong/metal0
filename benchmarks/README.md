# Lance vs Parquet Benchmarks

Benchmarks demonstrating Lance advantages over Parquet for analytics workloads.

## Quick Results

| Feature | Lance | Parquet |
|---------|-------|---------|
| Time Travel | ✅ Native | ❌ Not supported |
| Row Updates | ✅ O(1) | ❌ Full rewrite |
| Row Deletes | ✅ O(1) | ❌ Full rewrite |
| Vector Search | ✅ Native ANN | ❌ Requires external index |
| Query Speed | ✅ Fast | ✅ Fast |
| Compression | ✅ Good | ✅ Good |

## LanceQL vs lancedb Results

LanceQL is our Zig-based Lance reader with zero-copy Arrow C Data Interface.

| Benchmark | LanceQL | lancedb | Notes |
|-----------|---------|---------|-------|
| Column Projection | **12.95x faster** | - | Zero-copy Arrow path |
| Full Scan (100K) | 0.6x | **1.55x faster** | String column overhead |
| Full Scan (1M) | 0.3x | **3.58x faster** | String column overhead |
| Full Scan (10M) | **3.8x faster** | - | Zero-copy wins at scale |

### Zero-Copy Arrow Implementation

LanceQL uses the Arrow C Data Interface for zero-copy data sharing:

1. **Int64/Float64 columns**: Zero-copy via `ArrowArray` - data stays in Zig memory
2. **String columns**: Still requires copying (future work)
3. **At scale (10M+ rows)**: Zero-copy benefits outweigh Python/C boundary overhead

## Benchmarks

### 1. Time Travel
Query historical versions without copying data.

```bash
python benchmarks/01_time_travel.py
```

### 2. Updates & Deletes
Update/delete rows without rewriting entire file.

```bash
python benchmarks/02_updates.py
```

### 3. Vector Search
Semantic similarity search with ANN index.

```bash
python benchmarks/03_vector_search.py
```

### 4. Query Speed
Column pruning and predicate pushdown performance.

```bash
python benchmarks/04_query_speed.py
```

### 5. Compression
File size comparison for same data.

```bash
python benchmarks/05_compression.py
```

### 6. Read Performance (LanceQL vs lancedb)
Compare our Zig reader against the official lancedb library.

```bash
python benchmarks/06_read_performance.py
```

### 7. Query Performance (LanceQL vs lancedb)
SQL query execution comparison.

```bash
python benchmarks/07_query_performance.py
```

### 8. Scale Tests
Large dataset tests (100K, 1M, 10M rows) with memory tracking.

```bash
python benchmarks/08_scale_tests.py
```

## Run All

```bash
python benchmarks/run_all.py
```

## Requirements

```bash
pip install pyarrow pandas lancedb faiss-cpu numpy tqdm
```
