#!/bin/bash
# List Operations Benchmark
# Tests: append, pop, insert, slicing, list comprehension
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "List Operations Benchmark"
echo ""
echo "Tests: 1M appends, 1M pops, 10K inserts, 1M slices, 1M comprehension"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > list_bench.py <<'EOF'
def benchmark():
    # 1. Append
    arr = []
    i = 0
    while i < 1000000:
        arr.append(i)
        i = i + 1

    # 2. Pop
    while len(arr) > 0:
        arr.pop()

    # 3. Insert at front (smaller N - O(n) per insert)
    arr2 = []
    j = 0
    while j < 10000:
        arr2.insert(0, j)
        j = j + 1

    # 4. Slicing
    base = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    total = 0
    k = 0
    while k < 1000000:
        s = base[2:8]
        total = total + len(s)
        k = k + 1

    # 5. List comprehension
    result = [x * 2 for x in range(1000000)]

    print(len(result))
    print(total)

benchmark()
EOF

# Rust source
cat > list_bench.rs <<'EOF'
fn main() {
    // 1. Append (push)
    let mut arr: Vec<i64> = Vec::new();
    for i in 0..1_000_000i64 {
        arr.push(i);
    }

    // 2. Pop
    while !arr.is_empty() {
        arr.pop();
    }

    // 3. Insert at front
    let mut arr2: Vec<i64> = Vec::new();
    for j in 0..10_000i64 {
        arr2.insert(0, j);
    }

    // 4. Slicing
    let base: Vec<i64> = vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    let mut total: i64 = 0;
    for _ in 0..1_000_000 {
        let s = &base[2..8];
        total += s.len() as i64;
    }

    // 5. List comprehension (map + collect)
    let result: Vec<i64> = (0..1_000_000i64).map(|x| x * 2).collect();

    println!("{}", result.len());
    println!("{}", total);
}
EOF

# Go source
cat > list_bench.go <<'EOF'
package main

import "fmt"

func main() {
    // 1. Append
    arr := make([]int64, 0)
    for i := int64(0); i < 1000000; i++ {
        arr = append(arr, i)
    }

    // 2. Pop
    for len(arr) > 0 {
        arr = arr[:len(arr)-1]
    }

    // 3. Insert at front
    arr2 := make([]int64, 0)
    for j := int64(0); j < 10000; j++ {
        arr2 = append([]int64{j}, arr2...)
    }

    // 4. Slicing
    base := []int64{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
    total := int64(0)
    for k := 0; k < 1000000; k++ {
        s := base[2:8]
        total += int64(len(s))
    }

    // 5. List comprehension (manual)
    result := make([]int64, 1000000)
    for i := int64(0); i < 1000000; i++ {
        result[i] = i * 2
    }

    fmt.Println(len(result))
    fmt.Println(total)
}
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 list_bench.py list_bench_metal0
compile_rust list_bench.rs list_bench_rust
compile_go list_bench.go list_bench_go

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_metal0 BENCH_CMD list_bench_metal0
add_rust BENCH_CMD list_bench_rust
add_go BENCH_CMD list_bench_go
add_pypy BENCH_CMD list_bench.py
add_python BENCH_CMD list_bench.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f list_bench_metal0 list_bench_rust list_bench_go

echo ""
echo "Results saved to: results.md"
