#!/bin/bash
# bench-sql.sh - SQL Clause Benchmark (LanceQL vs DuckDB vs Polars)
#
# Benchmarks: SELECT *, WHERE, GROUP BY, ORDER BY LIMIT, DISTINCT, VECTOR SEARCH, HASH JOIN
# Dataset: 200M rows
# Each benchmark runs 30+ seconds.
#
# Usage: ./scripts/bench-sql.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "================================================================================"
echo "SQL Clause Benchmark (LanceQL vs DuckDB vs Polars)"
echo "================================================================================"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Platform: $(uname -s) $(uname -m)"
echo ""

# Check engines
echo "Engines:"
echo "  - LanceQL: native Zig + Metal GPU"

if python3 -c "import duckdb" 2>/dev/null; then
    echo "  - DuckDB: $(python3 -c 'import duckdb; print(duckdb.__version__)')"
else
    echo "  - DuckDB: not installed (pip install duckdb)"
fi

if python3 -c "import polars" 2>/dev/null; then
    echo "  - Polars: $(python3 -c 'import polars; print(polars.__version__)')"
else
    echo "  - Polars: not installed (pip install polars)"
fi
echo ""

echo "================================================================================"
echo "SQL Clauses Benchmark: End-to-End (Read + SQL Operations)"
echo "================================================================================"
echo ""
echo "Pipeline: Read file → execute SQL clause → return result"
echo "Each method runs for 15 seconds. Measuring throughput (rows/sec)."
echo ""

# Check for benchmark data files
LANCE_FILE="$PROJECT_DIR/benchmarks/benchmark_e2e.lance"
PARQUET_FILE="$PROJECT_DIR/benchmarks/benchmark_e2e.parquet"

echo "Data files:"
if [ -d "$LANCE_FILE" ]; then
    echo "  Lance:   benchmarks/benchmark_e2e.lance ✓"
else
    echo "  Lance:   benchmarks/benchmark_e2e.lance ✗"
fi

if [ -f "$PARQUET_FILE" ]; then
    echo "  Parquet: benchmarks/benchmark_e2e.parquet ✓"
else
    echo "  Parquet: benchmarks/benchmark_e2e.parquet ✗"
fi
echo ""

# Check if data files exist
if [ ! -d "$LANCE_FILE" ] || [ ! -f "$PARQUET_FILE" ]; then
    echo "⚠️  Missing data files. Run: python3 benchmarks/generate_benchmark_data.py"
    exit 0
fi

# Build and run
zig build bench-sql 2>&1
