#!/bin/bash
# Fan-out/Fan-in Benchmark Suite
# Compares: CPython, PyPy, metal0, Go, Rust

set -e
cd "$(dirname "$0")"

echo "========================================"
echo "   Fan-out/Fan-in Benchmark Suite"
echo "   1000 tasks x 10000 iterations each"
echo "========================================"
echo ""

# CPython
echo "--- CPython 3 (asyncio) ---"
python3 bench_fanout.py
echo ""

# PyPy
echo "--- PyPy 3 (asyncio) ---"
pypy3 bench_fanout.py
echo ""

# metal0 (compiled Python -> Zig)
echo "--- metal0 (Python -> Zig goroutines) ---"
../../zig-out/bin/metal0 bench_fanout.py 2>&1 | grep -E "^(Tasks|Work|Total|Time|Tasks/sec)" || true
echo ""

# Go
echo "--- Go (goroutines) ---"
go build -o bench_fanout_go bench_fanout.go 2>/dev/null
./bench_fanout_go
echo ""

# Rust
echo "--- Rust (tokio async) ---"
cd rust_bench
cargo build --release 2>/dev/null
./target/release/bench_fanout
cd ..
echo ""

echo "========================================"
echo "   Summary"
echo "========================================"
