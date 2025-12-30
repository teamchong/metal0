# LanceQL vs DuckDB vs Polars Feature Comparison

This document compares LanceQL features against DuckDB and Polars for feature parity tracking.

## Summary

| Category | LanceQL | DuckDB | Polars |
|----------|---------|--------|--------|
| Query Language | 95% | 100% | 95% |
| JOINs | Full | Full | Full |
| Window Functions | Full | Full | Full |
| Data Types | 90% | 100% | 95% |
| File Formats | Lance native | Many | Many |
| **Unique Features** | @logic_table | Extensions | LazyFrame |

## Detailed Comparison

### Query Language

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| SELECT / FROM / WHERE | Yes | Yes | Yes | Full support |
| ORDER BY / LIMIT | Yes | Yes | Yes | Full support |
| GROUP BY | Yes | Yes | Yes | Full support |
| HAVING | Yes | Yes | Yes | Full support |
| DISTINCT | Yes | Yes | Yes | Full support |

### JOINs

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| INNER JOIN | Yes | Yes | Yes | Hash join |
| LEFT JOIN | Yes | Yes | Yes | Hash join |
| RIGHT JOIN | Yes | Yes | Yes | Hash join |
| FULL OUTER JOIN | Yes | Yes | Yes | Hash join |
| CROSS JOIN | Yes | Yes | Yes | Nested loop |
| NATURAL JOIN | No | Yes | No | Future |
| LATERAL JOIN | No | Yes | No | Future |

### Set Operations

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| UNION | Yes | Yes | Yes | Full support |
| UNION ALL | Yes | Yes | Yes | Full support |
| INTERSECT | Yes | Yes | Yes | Full support |
| EXCEPT | Yes | Yes | Yes | Full support |

### Subqueries

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| Scalar subqueries | Yes | Yes | Yes | Full support |
| EXISTS / NOT EXISTS | Yes | Yes | Yes | Full support |
| IN (subquery) | Yes | Yes | Yes | Full support |
| IN (list) | Yes | Yes | Yes | Full support |
| Correlated subqueries | No | Yes | Limited | Future |
| CTEs (WITH clause) | No | Yes | No | Future |

### Window Functions

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| ROW_NUMBER | Yes | Yes | Yes | Full support |
| RANK | Yes | Yes | Yes | Full support |
| DENSE_RANK | Yes | Yes | Yes | Full support |
| NTILE | No | Yes | Yes | Future |
| LAG | Yes | Yes | Yes | Full support |
| LEAD | Yes | Yes | Yes | Full support |
| FIRST_VALUE | No | Yes | Yes | Future |
| LAST_VALUE | No | Yes | Yes | Future |
| Aggregate OVER | Yes | Yes | Yes | Full support |
| Frame bounds | No | Yes | Yes | Future |

### Aggregate Functions

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| COUNT / COUNT(*) | Yes | Yes | Yes | Full support |
| SUM | Yes | Yes | Yes | Full support |
| AVG | Yes | Yes | Yes | Full support |
| MIN / MAX | Yes | Yes | Yes | Full support |
| STDDEV / STDDEV_SAMP | Yes | Yes | Yes | Sample standard deviation |
| STDDEV_POP | Yes | Yes | Yes | Population standard deviation |
| VARIANCE / VAR_SAMP | Yes | Yes | Yes | Sample variance |
| VAR_POP | Yes | Yes | Yes | Population variance |
| PERCENTILE / QUANTILE | Yes | Yes | Yes | Arbitrary percentile (0-1) |
| MEDIAN | Yes | Yes | Yes | 50th percentile |
| STRING_AGG | No | Yes | Yes | Future |
| ARRAY_AGG | No | Yes | Yes | Future |

### Data Types

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| Integer (i64) | Yes | Yes | Yes | Full support |
| Float (f64) | Yes | Yes | Yes | Full support |
| String | Yes | Yes | Yes | Full support |
| Boolean | Yes | Yes | Yes | Full support |
| Date | Yes | Yes | Yes | Via epoch functions |
| Time | Yes | Yes | Yes | Via epoch functions |
| Timestamp | Yes | Yes | Yes | YEAR/MONTH/DAY/HOUR etc. |
| Interval | No | Yes | Yes | Future |
| Decimal | No | Yes | Yes | Future |
| UUID | No | Yes | No | Future |
| JSON | No | Yes | Yes | Future |
| List/Array | Partial | Yes | Yes | Read-only |
| Struct | No | Yes | Yes | Future |
| Map | No | Yes | No | Future |

### File Formats

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| Lance | **Yes** | No | No | Native format |
| Parquet | Via Lance | Yes | Yes | Lance reads Parquet |
| CSV | No | Yes | Yes | Future |
| JSON | No | Yes | Yes | Future |
| Arrow IPC | No | Yes | Yes | Future |
| Excel | No | Yes | Yes | Future |

### Performance Features

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| SIMD vectorization | Yes | Yes | Yes | 8-wide f64 |
| Parallel execution | Yes | Yes | Yes | Morsel-driven |
| mmap / zero-copy | Yes | Yes | Yes | Full support |
| Predicate pushdown | Yes | Yes | Yes | Full support |
| Projection pushdown | Yes | Yes | Yes | Full support |
| GPU acceleration | **Planned** | No | No | Metal only (macOS) |
| Streaming execution | No | Yes | Yes | Future |

### Unique LanceQL Features

| Feature | LanceQL | DuckDB | Polars | Notes |
|---------|---------|--------|--------|-------|
| @logic_table | **Yes** | No | No | Python compiled to native Zig |
| WASM browser support | Yes | Yes | No | 3KB module |
| HTTP Range requests | Yes | Yes | Yes | Full support |
| Vector search | **Yes** | Via ext | No | Native IVF-PQ index |
| Lance columnar format | **Yes** | No | No | Versioned, ML-optimized |

## Implementation Roadmap

### Phase 1: JOINs (P0 - High Priority) ✅ COMPLETE
- INNER JOIN with hash join algorithm
- LEFT/RIGHT/FULL JOIN extensions
- File: `src/sql/executor.zig:417`

### Phase 2: Window Functions (P1 - High Priority) ✅ COMPLETE
- ROW_NUMBER, RANK, DENSE_RANK
- LAG, LEAD
- Frame bounds (ROWS BETWEEN) - Future

### Phase 3: Set Operations (P2) ✅ COMPLETE
- UNION / UNION ALL
- INTERSECT
- EXCEPT

### Phase 4: Subqueries (P3) ✅ COMPLETE
- Scalar subquery evaluation
- EXISTS / NOT EXISTS execution
- IN (subquery) and IN (list) execution
- Simple (non-correlated) only

### Phase 5: Aggregations (P4) ✅ COMPLETE
- STDDEV / STDDEV_SAMP / STDDEV_POP ✅
- VARIANCE / VAR_SAMP / VAR_POP ✅
- PERCENTILE / QUANTILE / MEDIAN ✅
- STRING_AGG - Future

### Phase 6: Date/Time (P5) ✅ COMPLETE
- YEAR/MONTH/DAY/HOUR/MINUTE/SECOND extractors ✅
- DAYOFWEEK/DOW, DAYOFYEAR/DOY, WEEK, QUARTER ✅
- DATE_PART/EXTRACT(part, timestamp) ✅
- DATE_TRUNC(part, timestamp) ✅
- DATE_ADD/DATEADD(timestamp, interval, part) ✅
- DATE_DIFF/DATEDIFF(timestamp1, timestamp2, part) ✅
- EPOCH/UNIX_TIMESTAMP and FROM_UNIXTIME/TO_TIMESTAMP ✅

### Phase 7: File Formats (P6 - Optional)
- CSV reader
- JSON reader

## Benchmark Results

After optimization (vs DuckDB on 10M rows):

| Operation | LanceQL | DuckDB | Speedup |
|-----------|---------|--------|---------|
| FILTER | 3.2ms | 49ms | **15.3x** |
| AGGREGATE | 3.8ms | 80ms | **21.2x** |
| GROUP BY | 7.5ms | 85ms | **11.4x** |
| JOIN | 2.7ms | 88ms | **32.5x** |

Key optimizations:
- mmap + zero-copy I/O
- 8-wide SIMD (@Vector(8, f64))
- Morsel-driven parallelism (32K rows/thread)
