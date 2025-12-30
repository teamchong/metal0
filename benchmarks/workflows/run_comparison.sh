#!/bin/bash
#
# @logic_table Workflow Comparison: LanceQL vs DuckDB vs Polars
#
# This script runs the same workflows on all three engines:
# - DuckDB: SQL query + Python processing
# - Polars: DataFrame operations + Python processing
# - LanceQL: @logic_table (Python compiled to native, runs on GPU)
#
# Usage:
#   ./benchmarks/workflows/run_comparison.sh

set -e

cd "$(dirname "$0")/../.."

echo "================================================================================"
echo "@logic_table Workflow Comparison: LanceQL vs DuckDB vs Polars"
echo "================================================================================"
echo ""
echo "Workflows tested:"
echo "  1. Fraud Detection - 5-column risk scoring + filter"
echo "  2. Recommendation - Vector search (384-dim) + business rules"
echo "  3. Feature Engineering - 5 derived columns"
echo ""
echo "Data: 1,000,000 rows"
echo ""

# Check dependencies
echo "Checking dependencies..."
python3 -c "import duckdb" 2>/dev/null || { echo "Install duckdb: pip install duckdb"; exit 1; }
python3 -c "import polars" 2>/dev/null || { echo "Install polars: pip install polars"; exit 1; }
python3 -c "import numpy" 2>/dev/null || { echo "Install numpy: pip install numpy"; exit 1; }

# Build LanceQL benchmarks
echo "Building LanceQL benchmarks..."
zig build bench-logic-table 2>/dev/null || true

echo ""
echo "================================================================================"
echo "DuckDB Benchmark (SQL + Python)"
echo "================================================================================"
python3 benchmarks/workflows/bench_duckdb.py

echo ""
echo "================================================================================"
echo "Polars Benchmark (DataFrame + Python)"
echo "================================================================================"
python3 benchmarks/workflows/bench_polars.py

echo ""
echo "================================================================================"
echo "LanceQL @logic_table Benchmark (Python -> Native GPU)"
echo "================================================================================"
echo ""
echo "Running native Zig benchmark (actual @logic_table performance):"
echo ""
zig build bench-logic-table 2>&1 | grep -E "(LanceQL|Workflow|Dataset|---)" || true

echo ""
echo "================================================================================"
echo "Comparison Summary"
echo "================================================================================"
echo ""
echo "The key difference:"
echo ""
echo "  DuckDB/Polars:  [Query Engine] --fetch--> [Python] --process--> [Result]"
echo "                   Data crosses boundary, Python interprets business logic"
echo ""
echo "  LanceQL:        [Query Engine + @logic_table] ---> [Result]"
echo "                   Business logic compiled to native, runs ON data with GPU"
echo ""
echo "Benefits of @logic_table:"
echo "  - No data serialization between query engine and app"
echo "  - No Python interpreter overhead for business logic"
echo "  - GPU acceleration for vector search and batch operations"
echo "  - Single pass through data (no intermediate materialization)"
echo ""
