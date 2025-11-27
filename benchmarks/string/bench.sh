#!/bin/bash
# String Benchmark - Comparison and length operations
# Compares PyAOT vs Python vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark "String Benchmark - 100M iterations"
echo ""
echo "String comparison and length operations"
echo ""

# Python source (SAME code for PyAOT, Python, PyPy)
cat > string.py <<'EOF'
def benchmark():
    n = 100000000

    # 1. String comparison
    a = "test_string_alpha_one"
    b = "test_string_alpha_two"
    matches = 0
    j = 0
    while j < n:
        if a == a:
            matches = matches + 1
        if a != b:
            matches = matches + 1
        j = j + 1

    # 2. Length operations
    total_len = 0
    k = 0
    while k < n:
        total_len = total_len + len(a)
        k = k + 1

    print(matches)
    print(total_len)

benchmark()
EOF

echo "Building..."
build_pyaot_compiler
compile_pyaot string.py string_pyaot

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 3 --runs 5 --export-markdown results.md)

add_pyaot BENCH_CMD string_pyaot
add_pypy BENCH_CMD string.py
add_python BENCH_CMD string.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f string_pyaot

echo ""
echo "Results saved to: results.md"
