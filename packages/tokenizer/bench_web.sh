#!/bin/bash
# Web/Node.js tokenizer benchmarks (hyperfine-based)
set -e

echo "⚡ Web/Node.js Benchmark: All Libraries (realistic corpus)"
echo "============================================================"
echo "Encoding: 583 diverse texts (200K chars) × 100 iterations"
echo "Following industry standards: realistic diverse corpus"
echo ""

# Generate benchmark data if needed
if [ ! -f benchmark_data.json ]; then
    echo "Generating realistic benchmark data..."
    python3 generate_benchmark_data.py
    echo ""
fi

# Make scripts executable
chmod +x bench_web_gpt.js bench_web_tiktoken.js

echo "⚠️  Skipping @anthropic-ai/tokenizer - too slow (>5min for this benchmark)"
echo ""

# Run hyperfine
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_web_results.md \
    --command-name "gpt-tokenizer (JS)" 'node bench_web_gpt.js' \
    --command-name "tiktoken (Node)" 'node bench_web_tiktoken.js'

echo ""
echo "📊 Results saved to bench_web_results.md"
