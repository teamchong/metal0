#!/bin/bash
# Async I/O-bound Benchmark - Concurrent Sleep
# Compares metal0 vs Rust vs Go vs Python vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Async I/O Benchmark - Concurrent Sleep"
echo ""
echo "10,000 async tasks, 100ms sleep each"
echo "Sequential: 1,000,000ms (16.7 min). Measures concurrency factor."
echo ""

# Python source is already in bench_io.py

# Build metal0 compiler and compile benchmark
echo "Building..."
build_metal0_compiler

# Compile metal0 version
cd "$PROJECT_ROOT"
./zig-out/bin/metal0 "$SCRIPT_DIR/bench_io.py" --force >/dev/null 2>&1
if [ -f "build/lib.macosx-11.0-arm64/bench_io.cpython-312-darwin.so" ]; then
    cp "build/lib.macosx-11.0-arm64/bench_io.cpython-312-darwin.so" "$SCRIPT_DIR/bench_io_metal0"
    chmod +x "$SCRIPT_DIR/bench_io_metal0"
    echo -e "  ${GREEN}✓${NC} metal0: bench_io.py"
else
    echo -e "  ${RED}✗${NC} metal0: bench_io.py failed"
fi
cd "$SCRIPT_DIR"

# Compile Rust version
if [ "$RUST_AVAILABLE" = true ]; then
    cd rust_bench
    cargo build --bin bench_io --release >/dev/null 2>&1
    if [ -f "target/release/bench_io" ]; then
        echo -e "  ${GREEN}✓${NC} Rust: bench_io.rs"
        cp target/release/bench_io ../bench_io_rust
    fi
    cd ..
fi

# Compile Go version
if [ "$GO_AVAILABLE" = true ]; then
    CGO_ENABLED=0 go build -ldflags="-s -w" -o bench_io_go bench_io.go 2>/dev/null
    if [ -f "bench_io_go" ]; then
        echo -e "  ${GREEN}✓${NC} Go: bench_io.go"
    fi
fi

print_header "Running Benchmarks"
# Use fewer runs since I/O benchmarks are slower
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results_io.md)

# Add benchmarks in order: compiled first, then JIT, then interpreted
if [ -f "bench_io_metal0" ]; then
    BENCH_CMD+=(--command-name "metal0" "./bench_io_metal0")
fi

if [ -f "bench_io_rust" ]; then
    BENCH_CMD+=(--command-name "Rust" "./bench_io_rust")
fi

if [ -f "bench_io_go" ]; then
    BENCH_CMD+=(--command-name "Go" "./bench_io_go")
fi

add_pypy BENCH_CMD bench_io.py
add_python BENCH_CMD bench_io.py

"${BENCH_CMD[@]}"

# Cleanup binaries
rm -f bench_io_metal0 bench_io_rust bench_io_go

echo ""
echo "Results saved to: results_io.md"
