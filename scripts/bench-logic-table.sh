#!/bin/bash
# bench-logic-table.sh - @logic_table ML Workflow Benchmark (LanceQL vs DuckDB vs Polars)
#
# Benchmarks:
#   - Feature Engineering (1B rows): normalize, z-score, log transform
#   - Vector Search (10M docs x 384-dim): cosine similarity, euclidean distance
#   - Fraud Detection (500M transactions): multi-factor risk scoring
#   - Recommendations (5M items x 256-dim): collaborative filtering
#   - SQL Clauses (200M rows): SELECT, WHERE, GROUP BY, ORDER BY
#
# Each benchmark runs 30+ seconds.
#
# Usage: ./scripts/bench-logic-table.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "================================================================================"
echo "@logic_table ML Workflow Benchmark (LanceQL vs DuckDB vs Polars)"
echo "================================================================================"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Platform: $(uname -s) $(uname -m)"
echo ""

# Check engines
echo "Engines:"
echo "  - LanceQL: native Zig + Metal GPU (compiled @logic_table)"

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

# Build vector_ops.a if not present (required for @logic_table benchmarks)
if [ ! -f "$PROJECT_DIR/lib/vector_ops.a" ]; then
    echo "Building @logic_table library..."

    # Check if metal0 is built
    if [ ! -f "$PROJECT_DIR/deps/metal0/zig-out/bin/metal0" ]; then
        echo "  Building metal0 AOT Python compiler..."
        (cd "$PROJECT_DIR/deps/metal0" && zig build)
    fi

    # Compile Python @logic_table to native static library
    mkdir -p "$PROJECT_DIR/lib"
    "$PROJECT_DIR/deps/metal0/zig-out/bin/metal0" build --emit-logic-table "$PROJECT_DIR/benchmarks/vector_ops.py" -o "$PROJECT_DIR/lib/vector_ops.a"

    if [ ! -f "$PROJECT_DIR/lib/vector_ops.a" ]; then
        echo "ERROR: Failed to compile @logic_table library"
        exit 1
    fi
    echo "  ✓ Compiled lib/vector_ops.a"
fi

# Build and run
zig build bench-logic-table 2>&1
