#!/bin/bash
# Generator/Iterator Benchmark
# Tests: generator function, generator expression, lazy evaluation
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Generator/Iterator Benchmark"
echo ""
echo "Tests: yield 1M values, generator expressions, sum with generator"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > generator_bench.py <<'EOF'
def gen_numbers(n: int):
    i = 0
    while i < n:
        yield i
        i = i + 1

def benchmark():
    # 1. Generator function - consume all values
    total = 0
    for x in gen_numbers(1000000):
        total = total + x

    # 2. Generator expression
    total2 = 0
    gen_expr = (x * 2 for x in range(1000000))
    for x in gen_expr:
        total2 = total2 + x

    # 3. sum() with generator (lazy)
    total3 = sum(x for x in range(1000000))

    print(total)
    print(total2)
    print(total3)

benchmark()
EOF

# Rust source (iterators - no direct generator equivalent)
cat > generator_bench.rs <<'EOF'
fn main() {
    // 1. Iterator (equivalent to generator)
    let total: i64 = (0..1_000_000i64).sum();

    // 2. Iterator with map (equivalent to generator expression)
    let total2: i64 = (0..1_000_000i64).map(|x| x * 2).sum();

    // 3. sum() with iterator (lazy evaluation)
    let total3: i64 = (0..1_000_000i64).sum();

    println!("{}", total);
    println!("{}", total2);
    println!("{}", total3);
}
EOF

# Go source (manual loops - no iterators)
cat > generator_bench.go <<'EOF'
package main

import "fmt"

func main() {
    // 1. Manual loop (Go has no generators)
    total := int64(0)
    for i := int64(0); i < 1000000; i++ {
        total += i
    }

    // 2. Map equivalent
    total2 := int64(0)
    for i := int64(0); i < 1000000; i++ {
        total2 += i * 2
    }

    // 3. Sum
    total3 := int64(0)
    for i := int64(0); i < 1000000; i++ {
        total3 += i
    }

    fmt.Println(total)
    fmt.Println(total2)
    fmt.Println(total3)
}
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 generator_bench.py generator_bench_metal0
compile_rust generator_bench.rs generator_bench_rust
compile_go generator_bench.go generator_bench_go

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_metal0 BENCH_CMD generator_bench_metal0
add_rust BENCH_CMD generator_bench_rust
add_go BENCH_CMD generator_bench_go
add_pypy BENCH_CMD generator_bench.py
add_python BENCH_CMD generator_bench.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f generator_bench_metal0 generator_bench_rust generator_bench_go

echo ""
echo "Results saved to: results.md"
