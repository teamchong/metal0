#!/bin/bash
# Web/Node.js tokenizer benchmarks (hyperfine-based)
set -e

echo "⚡ Web/Node.js Benchmark: All 4 Libraries (realistic corpus)"
echo "============================================================"
echo "Encoding: 583 diverse texts (200K chars) × 1000 iterations"
echo "Node.js startup overhead <2% with 1000 iterations"
echo ""

# Generate benchmark data if needed
if [ ! -f benchmark_data.json ]; then
    echo "Generating realistic benchmark data..."
    python3 generate_benchmark_data.py
    echo ""
fi

# Make scripts executable
chmod +x bench_web_pyaot.js bench_web_ai.js bench_web_gpt.js bench_web_tiktoken.js

echo "📊 Benchmarking ALL 4 libraries:"
echo "   1. PyAOT (WASM)"
echo "   2. @anthropic-ai/tokenizer (JS)"
echo "   3. gpt-tokenizer (JS)"
echo "   4. tiktoken (Node)"
echo ""

# Run hyperfine with ALL 4 libraries (3 minute timeout per run)
timeout 180 hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_web_results.md \
    --ignore-failure \
    --command-name "PyAOT (WASM)" 'node bench_web_pyaot.js' \
    --command-name "@anthropic-ai/tokenizer (JS)" 'node bench_web_ai.js' \
    --command-name "gpt-tokenizer (JS)" 'node bench_web_gpt.js' \
    --command-name "tiktoken (Node)" 'node bench_web_tiktoken.js'

echo ""
echo "📊 Results saved to bench_web_results.md"
