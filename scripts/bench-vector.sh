#!/bin/bash
# bench-vector.sh - Vector Operations Benchmark (GPU vs CPU)
#
# Benchmarks:
#   - Batch cosine similarity (100K, 1M, 10M vectors x 384-dim)
#   - Single vector ops: dot product, cosine sim, L2 distance
#
# Each benchmark runs 30+ seconds.
#
# Usage: ./scripts/bench-vector.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "================================================================================"
echo "Vector Operations Benchmark (GPU vs CPU)"
echo "================================================================================"
echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Platform: $(uname -s) $(uname -m)"
echo ""

# Build and run
zig build bench-vector 2>&1
