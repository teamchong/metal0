#!/bin/bash
#
# LanceQL vs DuckDB Hot Execution Benchmark
#
# Measures hot execution time (after warmup) for fair apple-to-apple comparison.
# Both engines execute the same in-memory operations.
#
# Usage:
#   ./benchmarks/run_comparison.sh
#
# Requirements:
#   - zig build (already built)
#   - duckdb CLI installed

set -e

WARMUP=5
ITERATIONS=20
ROWS=1000000

echo "============================================================"
echo "LanceQL vs DuckDB Benchmark (Hot Execution)"
echo "============================================================"
echo "Warmup: $WARMUP iterations (excluded from timing)"
echo "Measured: $ITERATIONS iterations"
echo "Dataset: $ROWS rows"
echo ""

# Check for DuckDB
if ! command -v duckdb &> /dev/null; then
    echo "Error: duckdb CLI not found. Install with: brew install duckdb"
    exit 1
fi

echo "DuckDB version: $(duckdb --version 2>&1 | head -1)"
echo ""

# Create temp directory for test data
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Generate test parquet file using DuckDB
echo "Generating test data ($ROWS rows)..."
duckdb -c "COPY (
    SELECT
        i AS id,
        random() AS value,
        i % 100 AS group_key,
        'item_' || (i % 1000) AS name
    FROM range($ROWS) t(i)
) TO '$TMPDIR/test.parquet' (FORMAT PARQUET);"
echo "Test file: $TMPDIR/test.parquet ($(du -h $TMPDIR/test.parquet | cut -f1))"
echo ""

# Time a command with warmup using shell built-in time
# Returns average time in milliseconds
time_cmd() {
    local cmd="$1"
    local warmup=$2
    local iters=$3

    # Warmup (discard)
    for i in $(seq 1 $warmup); do
        eval "$cmd" > /dev/null 2>&1
    done

    # Timed iterations using date +%s%N for nanoseconds (macOS needs gdate)
    local total_ns=0
    for i in $(seq 1 $iters); do
        local start=$(perl -MTime::HiRes=time -e 'printf "%.9f", time')
        eval "$cmd" > /dev/null 2>&1
        local end=$(perl -MTime::HiRes=time -e 'printf "%.9f", time')
        local diff=$(echo "$end - $start" | bc)
        total_ns=$(echo "$total_ns + $diff" | bc)
    done

    # Calculate average in ms
    local avg_ms=$(echo "scale=2; $total_ns / $iters * 1000" | bc)
    echo "$avg_ms"
}

benchmark() {
    local name="$1"
    local duckdb_sql="$2"

    echo "------------------------------------------------------------"
    echo "$name"
    echo "------------------------------------------------------------"

    # DuckDB benchmark
    local duckdb_ms=$(time_cmd "duckdb -c \"$duckdb_sql\"" $WARMUP $ITERATIONS)
    echo "DuckDB:  ${duckdb_ms} ms"
    echo ""
}

echo "============================================================"
echo "SQL Clause Benchmarks (DuckDB only for now)"
echo "============================================================"
echo "(Run 'zig build bench-sql' for LanceQL results)"
echo ""

# Full Scan
benchmark "SELECT * LIMIT 10000" \
    "SELECT * FROM '$TMPDIR/test.parquet' LIMIT 10000"

# Projection
benchmark "SELECT id, value LIMIT 10000" \
    "SELECT id, value FROM '$TMPDIR/test.parquet' LIMIT 10000"

# Filter
benchmark "WHERE value > 0.5" \
    "SELECT COUNT(*) FROM '$TMPDIR/test.parquet' WHERE value > 0.5"

# Aggregation
benchmark "COUNT(*), SUM(value)" \
    "SELECT COUNT(*), SUM(value) FROM '$TMPDIR/test.parquet'"

# GROUP BY
benchmark "GROUP BY + COUNT" \
    "SELECT group_key, COUNT(*) FROM '$TMPDIR/test.parquet' GROUP BY group_key"

# ORDER BY LIMIT
benchmark "ORDER BY LIMIT 100" \
    "SELECT * FROM '$TMPDIR/test.parquet' ORDER BY value DESC LIMIT 100"

# DISTINCT
benchmark "DISTINCT name" \
    "SELECT DISTINCT name FROM '$TMPDIR/test.parquet'"

echo ""
echo "============================================================"
echo "LanceQL vs DuckDB Summary"
echo "============================================================"
echo ""
echo "To see side-by-side comparison, run both:"
echo "  1. DuckDB:  ./benchmarks/run_comparison.sh"
echo "  2. LanceQL: zig build bench-sql"
echo ""
echo "Note: LanceQL benchmarks run in-memory operations with GPU"
echo "acceleration, while this script runs DuckDB on parquet files."
echo "============================================================"
