#!/bin/bash
# NumPy Matrix Multiplication Benchmark
# Compares PyAOT (BLAS) vs Python (NumPy) vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark "NumPy Matrix Multiplication Benchmark - 500x500"
echo ""
echo "Matrix multiplication using BLAS (cblas_dgemm)"
echo "PyAOT calls BLAS directly, Python uses NumPy"
echo ""

# PyAOT source - uses numpy.ones and matmul
cat > matmul.py <<'EOF'
import numpy

# Create two 500x500 matrices filled with 1.0
n = 500
a = numpy.ones(n * n)
b = numpy.ones(n * n)

# Matrix multiplication: C = A @ B
# PyAOT signature: matmul(a, b, m, n, k) where A is m×k, B is k×n
result = numpy.matmul(a, b, n, n, n)  # type: ignore[call-overload]
print(numpy.sum(result))
EOF

# Python source - uses standard NumPy with same data
cat > matmul_numpy.py <<'EOF'
import numpy as np

# Create two 500x500 matrices filled with 1.0 (same as PyAOT)
size = 500
a = np.ones((size, size))
b = np.ones((size, size))

# Matrix multiplication
result = np.dot(a, b)
print(np.sum(result))
EOF

echo "Building..."
build_pyaot_compiler
compile_pyaot matmul.py matmul_pyaot

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 5 --export-markdown results.md)

add_pyaot BENCH_CMD matmul_pyaot
add_python BENCH_CMD matmul_numpy.py numpy
add_pypy BENCH_CMD matmul_numpy.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f matmul_pyaot

echo ""
echo "Results saved to: results.md"
