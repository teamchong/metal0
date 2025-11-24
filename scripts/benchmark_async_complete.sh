#!/bin/bash
set -e

echo "=================================="
echo "PyAOT vs Go: 5-Dimensional Async Benchmark"
echo "=================================="

# Check dependencies
command -v hyperfine >/dev/null || { echo "Install hyperfine: brew install hyperfine"; exit 1; }

# Build everything
echo -e "\n📦 Building..."
zig build -Doptimize=ReleaseFast > /dev/null 2>&1
echo "  ✓ PyAOT compiler built"

# Build PyAOT benchmarks
for f in examples/bench_{concurrency_final,cpu_bound,memory,latency,scalability}.py; do
    name=$(basename "$f" .py)
    ./zig-out/bin/pyaot build "$f" "./bench_${name}_pyaot" --binary > /dev/null 2>&1
done
echo "  ✓ PyAOT benchmarks built"

# Build Go benchmarks
for f in examples/bench_{concurrency_final,cpu_bound,memory,latency,scalability}_go.go; do
    name=$(basename "$f" _go.go)
    go build -o "./bench_${name}_go" "$f" 2> /dev/null
done
echo "  ✓ Go benchmarks built"

# Dimension 1: Throughput
echo -e "\n1️⃣  THROUGHPUT (100k concurrent tasks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PyAOT:"
hyperfine --warmup 1 --runs 3 './bench_concurrency_final_pyaot' 2>&1 | grep -E "Time|mean"
echo ""
echo "Go:"
hyperfine --warmup 1 --runs 3 './bench_concurrency_final_go' 2>&1 | grep -E "Time|mean"

# Dimension 2: Memory
echo -e "\n2️⃣  MEMORY (100k tasks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PyAOT:"
/usr/bin/time -l ./bench_memory_pyaot 2>&1 | grep "maximum resident" | awk '{printf "  Memory: %.1f MB (%.1f KB per task)\n", $1/1024/1024, $1/1024/100}'
echo ""
echo "Go:"
/usr/bin/time -l ./bench_memory_go 2>&1 | grep "maximum resident" | awk '{printf "  Memory: %.1f MB (%.1f KB per task)\n", $1/1024/1024, $1/1024/100}'

# Dimension 3: CPU Utilization
echo -e "\n3️⃣  CPU UTILIZATION (100 parallel CPU tasks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PyAOT:"
time ./bench_cpu_bound_pyaot 2>&1 | tail -3
echo ""
echo "Go:"
time ./bench_cpu_bound_go 2>&1 | tail -3
echo ""
echo "💡 Check: htop (all CPU cores should be 100%)"

# Dimension 4: Latency Distribution
echo -e "\n4️⃣  LATENCY DISTRIBUTION (10k tasks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PyAOT:"
./bench_latency_pyaot
echo ""
echo "Go:"
./bench_latency_go

# Dimension 5: Scalability
echo -e "\n5️⃣  SCALABILITY (1k → 10k → 100k tasks)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PyAOT:"
for n in 1000 10000 100000; do
    ./bench_scalability_pyaot $n
done
echo ""
echo "Go:"
for n in 1000 10000 100000; do
    ./bench_scalability_go $n
done

# Summary
echo -e "\n=================================="
echo "SUMMARY"
echo "=================================="
echo ""
echo "Compare results above across 5 dimensions:"
echo "  1. Throughput:  Faster = better"
echo "  2. Memory:      Lower = better"
echo "  3. CPU:         100% all cores = better"
echo "  4. Latency:     Lower p99 = better"
echo "  5. Scalability: Constant throughput = better"
echo ""
echo "🎯 Goal: Win 4/5 dimensions to be #1"
echo ""
