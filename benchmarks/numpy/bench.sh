#!/bin/bash
# NumPy Matrix Multiplication Benchmark
# Compares metal0 (BLAS) vs Python (NumPy) vs PyPy

source "$(dirname "$0")/../common.sh"
cd "$SCRIPT_DIR"

init_benchmark "NumPy Matrix Multiplication Benchmark - 500x500"
echo ""
echo "Matrix multiplication using BLAS (cblas_dgemm)"
echo "metal0 calls BLAS directly, Python uses NumPy"
echo ""

# metal0 source - uses numpy.ones and matmul
cat > matmul.py <<'EOF'
import numpy

# Create two 500x500 matrices filled with 1.0
n = 500
a = numpy.ones(n * n)
b = numpy.ones(n * n)

# Matrix multiplication: C = A @ B
# metal0 signature: matmul(a, b, m, n, k) where A is m×k, B is k×n
result = numpy.matmul(a, b, n, n, n)  # type: ignore[call-overload]
print(numpy.sum(result))
EOF

# Python source - uses standard NumPy with same data
cat > matmul_numpy.py <<'EOF'
import numpy as np

# Create two 500x500 matrices filled with 1.0 (same as metal0)
size = 500
a = np.ones((size, size))
b = np.ones((size, size))

# Matrix multiplication
result = np.dot(a, b)
print(np.sum(result))
EOF

echo "Building..."
build_metal0_compiler
compile_metal0 matmul.py matmul_metal0

print_header "Running Benchmarks"
BENCH_CMD=(hyperfine --warmup 1 --runs 5 --export-markdown results.md)

add_metal0 BENCH_CMD matmul_metal0
add_python BENCH_CMD matmul_numpy.py numpy
add_pypy BENCH_CMD matmul_numpy.py

"${BENCH_CMD[@]}"

# Cleanup
rm -f matmul_metal0

echo ""
echo "Results saved to: results.md"
