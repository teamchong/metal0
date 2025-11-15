#!/bin/bash
# Run all PyAOT benchmarks with hyperfine
# Compares CPython vs PyPy vs PyAOT (and Numba for NumPy)

set -e

echo "PyAOT Benchmark Suite"
echo "===================="
echo ""

# Check if tools are installed
command -v hyperfine >/dev/null 2>&1 || { echo "Error: hyperfine not installed. Run: brew install hyperfine"; exit 1; }

# Check Python
PYTHON="python"
echo "✓ CPython: $(python --version 2>&1)"

# Check for PyPy
PYPY=""
if command -v pypy3 >/dev/null 2>&1; then
    PYPY="pypy3"
    echo "✓ PyPy: $(pypy3 --version 2>&1 | head -1)"
else
    echo "⚠ PyPy not found (optional)"
    echo "  Install: brew install pypy3"
fi

# Check for Numba
NUMBA=""
if python -c "import numba" 2>/dev/null; then
    NUMBA="yes"
    echo "✓ Numba: $(python -c 'import numba; print(numba.__version__)')"
else
    echo "⚠ Numba not found (optional, for NumPy benchmarks)"
    echo "  Install: uv pip install numba"
fi

# Check for PyAOT
PYAOT=""
if command -v pyaot >/dev/null 2>&1; then
    PYAOT="yes"
    echo "✓ PyAOT: $(pyaot --version 2>&1 || echo 'installed')"
else
    echo "⚠ PyAOT not installed"
    echo "  Install: make install"
fi

echo ""

# Function to run benchmark
run_benchmark() {
    local name=$1
    local file=$2
    local skip_pyaot=${3:-no}

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Benchmark: $name"
    echo "File: $file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Build command array
    local commands=()

    commands+=("python $file")

    if [ -n "$PYPY" ]; then
        commands+=("pypy3 $file")
    fi

    if [ "$skip_pyaot" != "yes" ] && [ -n "$PYAOT" ]; then
        commands+=("pyaot $file")
    fi

    # Run hyperfine
    if [ ${#commands[@]} -eq 1 ]; then
        # Only CPython available
        hyperfine --warmup 2 --runs 3 \
            --export-markdown "benchmarks/${name}_results.md" \
            "${commands[@]}"
    else
        # Multiple implementations
        hyperfine --warmup 2 --runs 3 \
            --export-markdown "benchmarks/${name}_results.md" \
            "${commands[@]}"
    fi

    echo ""
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 1: Basic Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_benchmark "fibonacci" "benchmarks/fibonacci.py"
run_benchmark "loop_sum" "benchmarks/loop_sum.py"
run_benchmark "string_concat" "benchmarks/string_concat.py"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 2: JSON Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_benchmark "json_parse" "benchmarks/json_bench.py"
run_benchmark "json_simd" "benchmarks/json_simd_bench.py"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PART 3: NumPy Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if NumPy is available
if ! python -c "import numpy" 2>/dev/null; then
    echo "⚠ NumPy not installed - skipping NumPy benchmarks"
    echo "  Install: uv pip install numpy"
    echo ""
else
    echo "Running NumPy benchmarks..."
    echo ""

    # Basic NumPy benchmark
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "NumPy Operations (CPython vs PyPy vs PyAOT)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Build NumPy benchmark commands
    NUMPY_COMMANDS=("python benchmarks/numpy_bench.py")

    if [ -n "$PYPY" ]; then
        if pypy3 -c "import numpy" 2>/dev/null; then
            NUMPY_COMMANDS+=("pypy3 benchmarks/numpy_bench.py")
        fi
    fi

    if [ -n "$PYAOT" ]; then
        # PyAOT needs VIRTUAL_ENV set
        NUMPY_COMMANDS+=("uv run pyaot benchmarks/numpy_bench.py")
    fi

    hyperfine --warmup 2 --runs 3 \
        --export-markdown "benchmarks/numpy_results.md" \
        "${NUMPY_COMMANDS[@]}"

    echo ""

    # Numba benchmark (if available)
    if [ -n "$NUMBA" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "NumPy with Numba JIT (CPython vs CPython+Numba vs PyAOT)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        NUMBA_COMMANDS=("python benchmarks/numpy_numba_bench.py")

        if [ -n "$PYAOT" ]; then
            NUMBA_COMMANDS+=("uv run pyaot benchmarks/numpy_numba_bench.py")
        fi

        hyperfine --warmup 2 --runs 3 \
            --export-markdown "benchmarks/numpy_numba_results.md" \
            "${NUMBA_COMMANDS[@]}"

        echo ""
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ All benchmarks complete!"
echo ""
echo "Results saved to benchmarks/*_results.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
