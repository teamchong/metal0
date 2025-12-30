#!/bin/bash
# bench-all.sh - Run all LanceQL benchmarks
#
# Runs all benchmarks in sequence:
#   1. bench-vector.sh   - GPU vs CPU vector operations
#   2. bench-sql.sh      - SQL clauses (LanceQL vs DuckDB vs Polars)
#   3. bench-logic-table.sh - ML workflows (LanceQL vs DuckDB vs Polars)
#
# Each individual benchmark runs 30+ seconds per operation.
# Total runtime: ~10-15 minutes
#
# Usage: ./scripts/bench-all.sh [--summary]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

SUMMARY_ONLY=false
if [[ "${1:-}" == "--summary" ]]; then
    SUMMARY_ONLY=true
fi

# Output file for CI job summary
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/benchmark-results.txt}"

echo "================================================================================"
echo "LanceQL Benchmark Suite"
echo "================================================================================"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Platform: $(uname -s) $(uname -m)"
echo "Output: $OUTPUT_FILE"
echo ""

# Clear output file
> "$OUTPUT_FILE"

run_benchmark() {
    local name=$1
    local script=$2

    echo ""
    echo "================================================================================"
    echo "Running: $name"
    echo "================================================================================"
    echo ""

    # Run and capture output
    if "$SCRIPT_DIR/$script" 2>&1 | tee -a "$OUTPUT_FILE"; then
        echo ""
        echo "[$name] COMPLETED"
    else
        echo ""
        echo "[$name] FAILED"
        return 1
    fi
}

# Build first
echo "Building LanceQL..."
zig build lib 2>&1 | tee -a "$OUTPUT_FILE"
echo ""

# Run all benchmarks
run_benchmark "Vector Operations (GPU vs CPU)" "bench-vector.sh"
run_benchmark "SQL Clauses (LanceQL vs DuckDB vs Polars)" "bench-sql.sh"
run_benchmark "ML Workflows (LanceQL vs DuckDB vs Polars)" "bench-logic-table.sh"

echo ""
echo "================================================================================"
echo "All Benchmarks Complete"
echo "================================================================================"
echo "Results saved to: $OUTPUT_FILE"
echo ""

# Print summary for CI
if [[ "$SUMMARY_ONLY" == "true" ]] || [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo ""
    echo "## Benchmark Summary"
    echo ""
    grep -E "(LanceQL|DuckDB|Polars|Winner|Throughput|M/sec|rows/s)" "$OUTPUT_FILE" | head -50
fi
