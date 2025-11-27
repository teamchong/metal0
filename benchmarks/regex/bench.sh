#!/bin/bash
# Regex Benchmark - PyAOT regex vs Python vs Rust vs Go
# Tests common regex patterns against realistic data

source "$(dirname "$0")/../common.sh"

REGEX_PKG="$PROJECT_ROOT/packages/regex"

init_benchmark_compiled "Regex Benchmark"
echo ""
echo "Tests: Email, URL, Digits, Word Boundary, Date ISO patterns"
echo ""

# Check if regex package exists
if [ ! -d "$REGEX_PKG" ]; then
    echo -e "${RED}Error: packages/regex not found${NC}"
    exit 1
fi

cd "$REGEX_PKG"

echo "Building..."

# Build Zig (PyAOT regex)
zig build -Doptimize=ReleaseFast >/dev/null 2>&1
[ -f "./zig-out/bin/bench_zig" ] && echo -e "  ${GREEN}✓${NC} Zig/PyAOT"

# Build Rust
if [ "$RUST_AVAILABLE" = true ]; then
    cargo build --release --quiet 2>/dev/null
    [ -f "./target/release/bench_rust" ] && echo -e "  ${GREEN}✓${NC} Rust"
fi

# Build Go
if [ "$GO_AVAILABLE" = true ]; then
    CGO_ENABLED=0 go build -ldflags="-s -w" -o bench_go bench_go.go 2>/dev/null
    [ -f "./bench_go" ] && echo -e "  ${GREEN}✓${NC} Go"
fi

print_header "Running Benchmarks"
echo ""

# Run Python
echo "Python (re module):"
python3 bench_python.py
echo ""

# Run PyPy
if [ "$PYPY_AVAILABLE" = true ]; then
    echo "PyPy (re module):"
    pypy3 bench_python.py
    echo ""
fi

# Run Zig/PyAOT
if [ -f "./zig-out/bin/bench_zig" ]; then
    echo "Zig/PyAOT:"
    ./zig-out/bin/bench_zig
    echo ""
fi

# Run Rust
if [ -f "./target/release/bench_rust" ]; then
    echo "Rust:"
    ./target/release/bench_rust
    echo ""
fi

# Run Go
if [ -f "./bench_go" ]; then
    echo "Go:"
    ./bench_go
    echo ""
fi

echo "Done!"
