#!/bin/bash
# Async CPU-bound Benchmark - SHA256 hashing
# Compares metal0 vs Rust vs Go vs Python vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Async CPU Benchmark - SHA256 Hashing"
echo ""
echo "100 async tasks, 10K SHA256 hash iterations each"
echo ""

# Python source is already in bench_cpu.py

# Build metal0 compiler and compile benchmark
echo "Building..."
build_metal0_compiler

# Compile metal0 version - run directly without --binary (outputs to build/)
cd "$PROJECT_ROOT"
./zig-out/bin/metal0 "$SCRIPT_DIR/bench_cpu.py" --force >/dev/null 2>&1
# The binary is output to the current directory with same name as .so but executable
if [ -f "build/lib.macosx-11.0-arm64/bench_cpu.cpython-312-darwin.so" ]; then
    cp "build/lib.macosx-11.0-arm64/bench_cpu.cpython-312-darwin.so" "$SCRIPT_DIR/bench_cpu_metal0"
    chmod +x "$SCRIPT_DIR/bench_cpu_metal0"
    echo -e "  ${GREEN}✓${NC} metal0: bench_cpu.py"
else
    echo -e "  ${RED}✗${NC} metal0: bench_cpu.py failed"
fi
cd "$SCRIPT_DIR"

# Compile Rust version
if [ "$RUST_AVAILABLE" = true ]; then
    cd rust_bench
    cargo build --bin bench_cpu --release >/dev/null 2>&1
    if [ -f "target/release/bench_cpu" ]; then
        echo -e "  ${GREEN}✓${NC} Rust: bench_cpu.rs"
        cp target/release/bench_cpu ../bench_cpu_rust
    fi
    cd ..
fi

# Compile Go version
if [ "$GO_AVAILABLE" = true ]; then
    CGO_ENABLED=0 go build -ldflags="-s -w" -o bench_cpu_go bench_cpu.go 2>/dev/null
    if [ -f "bench_cpu_go" ]; then
        echo -e "  ${GREEN}✓${NC} Go: bench_cpu.go"
    fi
fi

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 5 --export-markdown results.md)

# Add benchmarks in order: compiled first, then JIT, then interpreted
if [ -f "bench_cpu_metal0" ]; then
    BENCH_CMD+=(--command-name "metal0" "./bench_cpu_metal0")
fi

if [ -f "bench_cpu_rust" ]; then
    BENCH_CMD+=(--command-name "Rust" "./bench_cpu_rust")
fi

if [ -f "bench_cpu_go" ]; then
    BENCH_CMD+=(--command-name "Go" "./bench_cpu_go")
fi

add_pypy BENCH_CMD bench_cpu.py
add_python BENCH_CMD bench_cpu.py

"${BENCH_CMD[@]}"

# Cleanup binaries
rm -f bench_cpu_metal0 bench_cpu_rust bench_cpu_go

echo ""
echo "Results saved to: results.md"
