#!/bin/bash
# Class/Object Operations Benchmark
# Tests: instance creation, attribute read/write, method calls
# All Python-based runners use the SAME source code

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark_compiled "Class/Object Operations Benchmark"
echo ""
echo "Tests: 100K instance creation, attr read/write, method calls"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > class_bench.py <<'EOF'
class Point:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

    def distance(self) -> int:
        return self.x * self.x + self.y * self.y

def benchmark():
    # 1. Instance creation
    points = []
    i = 0
    while i < 100000:
        p = Point(i, i + 1)
        points.append(p)
        i = i + 1

    # 2. Attribute read
    total_x = 0
    j = 0
    while j < len(points):
        total_x = total_x + points[j].x
        j = j + 1

    # 3. Attribute write
    k = 0
    while k < len(points):
        points[k].x = k * 2
        k = k + 1

    # 4. Method calls
    total_dist = 0
    m = 0
    while m < len(points):
        total_dist = total_dist + points[m].distance()
        m = m + 1

    print(total_x)
    print(total_dist)

benchmark()
EOF

# Rust source
cat > class_bench.rs <<'EOF'
struct Point {
    x: i64,
    y: i64,
}

impl Point {
    fn new(x: i64, y: i64) -> Self {
        Point { x, y }
    }

    fn distance(&self) -> i64 {
        self.x * self.x + self.y * self.y
    }
}

fn main() {
    // 1. Instance creation
    let mut points: Vec<Point> = Vec::new();
    for i in 0..100_000i64 {
        let p = Point::new(i, i + 1);
        points.push(p);
    }

    // 2. Attribute read
    let mut total_x: i64 = 0;
    for j in 0..points.len() {
        total_x += points[j].x;
    }

    // 3. Attribute write
    for k in 0..points.len() {
        points[k].x = (k * 2) as i64;
    }

    // 4. Method calls
    let mut total_dist: i64 = 0;
    for m in 0..points.len() {
        total_dist += points[m].distance();
    }

    println!("{}", total_x);
    println!("{}", total_dist);
}
EOF

# Go source
cat > class_bench.go <<'EOF'
package main

import "fmt"

type Point struct {
    X int64
    Y int64
}

func NewPoint(x, y int64) Point {
    return Point{X: x, Y: y}
}

func (p Point) Distance() int64 {
    return p.X*p.X + p.Y*p.Y
}

func main() {
    // 1. Instance creation
    points := make([]Point, 0)
    for i := int64(0); i < 100000; i++ {
        p := NewPoint(i, i+1)
        points = append(points, p)
    }

    // 2. Attribute read
    totalX := int64(0)
    for j := 0; j < len(points); j++ {
        totalX += points[j].X
    }

    // 3. Attribute write
    for k := 0; k < len(points); k++ {
        points[k].X = int64(k * 2)
    }

    // 4. Method calls
    totalDist := int64(0)
    for m := 0; m < len(points); m++ {
        totalDist += points[m].Distance()
    }

    fmt.Println(totalX)
    fmt.Println(totalDist)
}
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 class_bench.py class_bench_metal0
compile_rust class_bench.rs class_bench_rust
compile_go class_bench.go class_bench_go

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 3 --export-markdown results.md)

add_metal0 BENCH_CMD class_bench_metal0
add_rust BENCH_CMD class_bench_rust
add_go BENCH_CMD class_bench_go
add_pypy BENCH_CMD class_bench.py
add_python BENCH_CMD class_bench.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f class_bench_metal0 class_bench_rust class_bench_go

echo ""
echo "Results saved to: results.md"
