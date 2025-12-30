#!/bin/bash
#
# LanceQL vs DuckDB vs Polars Benchmark Comparison
#
# Runs the same queries on all three engines and compares performance.
#
# Prerequisites:
#   - zig build (builds lanceql CLI)
#   - duckdb CLI installed
#   - polars CLI installed (optional)
#
# Usage:
#   ./benchmarks/compare_engines.sh [data.parquet]

set -e

DATA_FILE="${1:-tests/fixtures/benchmark_100k.parquet}"
ITERATIONS=10

echo "============================================================"
echo "LanceQL vs DuckDB vs Polars Benchmark"
echo "============================================================"
echo "Data file: $DATA_FILE"
echo "Iterations: $ITERATIONS"
echo ""

# Check if data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "Creating test data file..."
    # Use DuckDB to create test data if available
    if command -v duckdb &> /dev/null; then
        duckdb -c "COPY (SELECT i AS id, random() AS value, 'item_' || (i % 100) AS name FROM range(100000) t(i)) TO '$DATA_FILE' (FORMAT PARQUET);"
    else
        echo "Error: Data file not found and duckdb not available to create it"
        exit 1
    fi
fi

# Build LanceQL CLI
echo "Building LanceQL..."
zig build 2>/dev/null || true

LANCEQL="./zig-out/bin/lanceql"
if [ ! -f "$LANCEQL" ]; then
    echo "Error: LanceQL CLI not found. Run 'zig build' first."
    exit 1
fi

# Check for DuckDB
DUCKDB=""
if command -v duckdb &> /dev/null; then
    DUCKDB="duckdb"
fi

# Check for Polars CLI
POLARS=""
if command -v polars &> /dev/null; then
    POLARS="polars"
fi

echo ""
echo "Available engines:"
echo "  - LanceQL: $LANCEQL"
[ -n "$DUCKDB" ] && echo "  - DuckDB: $DUCKDB" || echo "  - DuckDB: (not installed)"
[ -n "$POLARS" ] && echo "  - Polars: $POLARS" || echo "  - Polars: (not installed)"
echo ""

# Benchmark function
benchmark_query() {
    local name="$1"
    local query="$2"
    local duckdb_query="$3"

    echo "------------------------------------------------------------"
    echo "Benchmark: $name"
    echo "------------------------------------------------------------"

    # LanceQL
    echo ""
    echo "LanceQL:"
    $LANCEQL -b -i $ITERATIONS "$query" 2>&1 | grep -E "(Rows:|Min:|Avg:|Throughput:)" || true

    # DuckDB
    if [ -n "$DUCKDB" ]; then
        echo ""
        echo "DuckDB:"
        # DuckDB doesn't have built-in benchmark mode, so we time it
        start_time=$(python3 -c "import time; print(time.time())")
        for i in $(seq 1 $ITERATIONS); do
            $DUCKDB -c "$duckdb_query" > /dev/null 2>&1
        done
        end_time=$(python3 -c "import time; print(time.time())")
        avg_ms=$(python3 -c "print(f'{(($end_time - $start_time) / $ITERATIONS * 1000):.2f}')")
        echo "  Avg: $avg_ms ms (external timing)"
    fi

    echo ""
}

# Run benchmarks
echo "============================================================"
echo "SQL Clause Benchmarks"
echo "============================================================"

# 1. Full scan
benchmark_query "Full Scan (SELECT *)" \
    "SELECT * FROM '$DATA_FILE' LIMIT 1000" \
    "SELECT * FROM '$DATA_FILE' LIMIT 1000"

# 2. Projection
benchmark_query "Projection (SELECT col1, col2)" \
    "SELECT id, value FROM '$DATA_FILE' LIMIT 1000" \
    "SELECT id, value FROM '$DATA_FILE' LIMIT 1000"

# 3. Filter
benchmark_query "Filter (WHERE)" \
    "SELECT * FROM '$DATA_FILE' WHERE value > 0.5" \
    "SELECT * FROM '$DATA_FILE' WHERE value > 0.5"

# 4. Aggregation
benchmark_query "Aggregation (COUNT, SUM)" \
    "SELECT COUNT(*), SUM(value) FROM '$DATA_FILE'" \
    "SELECT COUNT(*), SUM(value) FROM '$DATA_FILE'"

# 5. GROUP BY
benchmark_query "GROUP BY" \
    "SELECT name, COUNT(*) FROM '$DATA_FILE' GROUP BY name" \
    "SELECT name, COUNT(*) FROM '$DATA_FILE' GROUP BY name"

# 6. ORDER BY LIMIT
benchmark_query "ORDER BY LIMIT (Top-K)" \
    "SELECT * FROM '$DATA_FILE' ORDER BY value DESC LIMIT 100" \
    "SELECT * FROM '$DATA_FILE' ORDER BY value DESC LIMIT 100"

# 7. DISTINCT
benchmark_query "DISTINCT" \
    "SELECT DISTINCT name FROM '$DATA_FILE'" \
    "SELECT DISTINCT name FROM '$DATA_FILE'"

echo ""
echo "============================================================"
echo "Benchmark Complete"
echo "============================================================"
