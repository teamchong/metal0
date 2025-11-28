#!/bin/bash
# Dict Benchmark - Lookup-heavy workload
# Compares metal0 vs Python vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark "Dict Benchmark - 10M lookups"
echo ""
echo "Static dict with 8 keys, 10M iterations"
echo ""

# Python source (SAME code for metal0, Python, PyPy)
cat > dict.py <<'EOF'
def benchmark():
    data = {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8}
    total = 0
    i = 0
    while i < 10000000:
        total = total + data["a"]
        total = total + data["b"]
        total = total + data["c"]
        total = total + data["d"]
        total = total + data["e"]
        total = total + data["f"]
        total = total + data["g"]
        total = total + data["h"]
        i = i + 1
    print(total)

benchmark()
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 dict.py dict_metal0

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 3 --runs 5 --export-markdown results.md)

add_metal0 BENCH_CMD dict_metal0
add_pypy BENCH_CMD dict.py
add_python BENCH_CMD dict.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f dict_metal0

echo ""
echo "Results saved to: results.md"
