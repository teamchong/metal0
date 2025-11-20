#!/bin/bash
# Hyperfine benchmark: Web/WASM tokenizers

# Build WASM if needed
if [ ! -f dist/tokenizer.wasm ]; then
    echo "Building WASM tokenizer..."
    zig build-lib src/tokenizer.zig -target wasm32-freestanding -O ReleaseFast -dynamic
    mkdir -p dist
    mv tokenizer.wasm dist/
fi

# Make bench_web.js executable
chmod +x bench_web.js

echo ""
echo "⚡ Web/WASM Tokenizer Benchmark (hyperfine)"
echo "============================================================"

# Run hyperfine
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_web_results.md \
    --command-name "PyAOT WASM" 'node bench_web.js'

echo ""
echo "✅ Results saved to bench_web_results.md"
