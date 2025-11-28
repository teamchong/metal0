#!/bin/bash
# Fibonacci Benchmark - Recursive fib(45)
# Compares metal0 vs Rust vs Go vs Python vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Fibonacci Benchmark - fib(45)"
echo ""
echo "Recursive fibonacci without memoization"
echo "Expected: ~3s compiled, ~12s PyPy, ~100s Python"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > fib.py <<'EOF'
def fib(n: int) -> int:
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

result = fib(45)
print(result)
EOF

# Rust source
cat > fib.rs <<'EOF'
fn fib(n: u64) -> u64 {
    if n <= 1 { n } else { fib(n - 1) + fib(n - 2) }
}

fn main() {
    let result = fib(45);
    println!("{}", result);
}
EOF

# Go source
cat > fib.go <<'EOF'
package main

import "fmt"

func fib(n uint64) uint64 {
    if n <= 1 { return n }
    return fib(n-1) + fib(n-2)
}

func main() {
    result := fib(45)
    fmt.Println(result)
}
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 fib.py fib_metal0
compile_rust fib.rs fib_rust
compile_go fib.go fib_go

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_metal0 BENCH_CMD fib_metal0
add_rust BENCH_CMD fib_rust
add_go BENCH_CMD fib_go
add_pypy BENCH_CMD fib.py
add_python BENCH_CMD fib.py

"${BENCH_CMD[@]}"

# Cleanup binaries
rm -f fib_metal0 fib_rust fib_go

echo ""
echo "Results saved to: results.md"
