#!/bin/bash
# Startup time benchmark: 4-Language comparison (Hello World)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

echo "⚡ Startup Time Benchmark: 4-Language Comparison"
echo "================================================="
echo "Measuring pure startup overhead (Hello World)"
echo ""

# Create build directory (gitignored)
mkdir -p "$BUILD_DIR"

# Pre-compile PyAOT binary
if [ ! -f ../.pyaot/hello ]; then
    echo "Compiling PyAOT binary..."
    cd ..
    pyaot build benchmarks/hello.py --binary
    cd "$SCRIPT_DIR"
    echo ""
fi

# Compile Go and Rust to build directory
go build -o "$BUILD_DIR/hello_go" hello.go
rustc -O hello.rs -o "$BUILD_DIR/hello_rust"

# Run hyperfine benchmark
hyperfine \
    --warmup 10 \
    --runs 100 \
    --shell=none \
    --export-markdown bench_startup_results.md \
    --command-name "PyAOT (Zig)" '../.pyaot/hello' \
    --command-name "Rust 1.91" "$BUILD_DIR/hello_rust" \
    --command-name "Go 1.25" "$BUILD_DIR/hello_go" \
    --command-name "CPython 3.13" 'python3 hello.py'

echo ""
echo "📊 Results saved to bench_startup_results.md"
