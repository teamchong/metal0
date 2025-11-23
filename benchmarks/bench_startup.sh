#!/bin/bash
# Startup time benchmark: CPython vs PyAOT (cold start)
set -e

echo "⚡ Startup Time Benchmark: Hello World"
echo "========================================"
echo "Measuring pure startup overhead (no computation)"
echo ""

# Pre-compile PyAOT binary
if [ ! -f ../.pyaot/hello ]; then
    echo "Compiling PyAOT binary..."
    cd ..
    pyaot build benchmarks/hello.py --binary
    cd benchmarks
    echo ""
fi

# Run hyperfine benchmark
hyperfine \
    --warmup 10 \
    --runs 100 \
    --shell=none \
    --export-markdown bench_startup_results.md \
    --command-name "CPython 3.13" 'python3 hello.py' \
    --command-name "PyAOT (native binary)" '../.pyaot/hello'

echo ""
echo "📊 Results saved to bench_startup_results.md"
