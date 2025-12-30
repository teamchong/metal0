#!/bin/bash
# Set Operations Benchmark
# Tests: add, membership, union, intersection, difference
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Set Operations Benchmark"
echo ""
echo "Tests: 1M adds, 1M membership, union/intersection/difference on 100K sets"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > set_bench.py <<'EOF'
def benchmark():
    # 1. Add
    s = set()
    i = 0
    while i < 1000000:
        s.add(i)
        i = i + 1

    # 2. Membership test
    found = 0
    j = 0
    while j < 1000000:
        if j in s:
            found = found + 1
        j = j + 1

    # 3. Build two sets for set operations
    a = set()
    b = set()
    k = 0
    while k < 100000:
        a.add(k)
        b.add(k + 50000)
        k = k + 1

    # 4. Union
    union_result = a | b

    # 5. Intersection
    inter_result = a & b

    # 6. Difference
    diff_result = a - b

    print(found)
    print(len(union_result))
    print(len(inter_result))
    print(len(diff_result))

benchmark()
EOF

# Rust source
cat > set_bench.rs <<'EOF'
use std::collections::HashSet;

fn main() {
    // 1. Add
    let mut s: HashSet<i64> = HashSet::new();
    for i in 0..1_000_000i64 {
        s.insert(i);
    }

    // 2. Membership test
    let mut found: i64 = 0;
    for j in 0..1_000_000i64 {
        if s.contains(&j) {
            found += 1;
        }
    }

    // 3. Build two sets
    let mut a: HashSet<i64> = HashSet::new();
    let mut b: HashSet<i64> = HashSet::new();
    for k in 0..100_000i64 {
        a.insert(k);
        b.insert(k + 50_000);
    }

    // 4. Union
    let union_result: HashSet<_> = a.union(&b).collect();

    // 5. Intersection
    let inter_result: HashSet<_> = a.intersection(&b).collect();

    // 6. Difference
    let diff_result: HashSet<_> = a.difference(&b).collect();

    println!("{}", found);
    println!("{}", union_result.len());
    println!("{}", inter_result.len());
    println!("{}", diff_result.len());
}
EOF

# Go source
cat > set_bench.go <<'EOF'
package main

import "fmt"

func main() {
    // 1. Add
    s := make(map[int64]struct{})
    for i := int64(0); i < 1000000; i++ {
        s[i] = struct{}{}
    }

    // 2. Membership test
    found := int64(0)
    for j := int64(0); j < 1000000; j++ {
        if _, ok := s[j]; ok {
            found++
        }
    }

    // 3. Build two sets
    a := make(map[int64]struct{})
    b := make(map[int64]struct{})
    for k := int64(0); k < 100000; k++ {
        a[k] = struct{}{}
        b[k+50000] = struct{}{}
    }

    // 4. Union
    union := make(map[int64]struct{})
    for k := range a { union[k] = struct{}{} }
    for k := range b { union[k] = struct{}{} }

    // 5. Intersection
    inter := make(map[int64]struct{})
    for k := range a {
        if _, ok := b[k]; ok { inter[k] = struct{}{} }
    }

    // 6. Difference
    diff := make(map[int64]struct{})
    for k := range a {
        if _, ok := b[k]; !ok { diff[k] = struct{}{} }
    }

    fmt.Println(found)
    fmt.Println(len(union))
    fmt.Println(len(inter))
    fmt.Println(len(diff))
}
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 set_bench.py set_bench_metal0
compile_rust set_bench.rs set_bench_rust
compile_go set_bench.go set_bench_go

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_metal0 BENCH_CMD set_bench_metal0
add_rust BENCH_CMD set_bench_rust
add_go BENCH_CMD set_bench_go
add_pypy BENCH_CMD set_bench.py
add_python BENCH_CMD set_bench.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f set_bench_metal0 set_bench_rust set_bench_go

echo ""
echo "Results saved to: results.md"
