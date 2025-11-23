#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building all benchmarks..."
echo

# Build Zig
echo "Building Zig benchmark..."
zig build -Doptimize=ReleaseFast

# Build Rust
echo "Building Rust benchmark..."
cargo build --release --quiet 2>/dev/null || cargo build --release

# Check if Go is available
if command -v go &> /dev/null; then
    echo "Building Go benchmark..."
    go build -o bench_go bench_go.go
else
    echo "Go not found, skipping Go benchmark"
fi

echo
echo "Running benchmarks..."
echo

# Run Python
echo "Running Python benchmark..."
python3 bench_python.py
echo

# Run Zig/PyAOT
echo "Running Zig/PyAOT benchmark..."
./zig-out/bin/bench_zig
echo

# Run Rust
echo "Running Rust benchmark..."
./target/release/bench_rust
echo

# Run Go if available
if [ -f bench_go ]; then
    echo "Running Go benchmark..."
    ./bench_go
    echo
fi

echo "Done!"
