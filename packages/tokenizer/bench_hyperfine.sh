#!/bin/bash
# Quick benchmark for rapid iteration (3 fastest libraries, 100 iterations)
set -e
cd "$(dirname "$0")"

echo "⚡ Quick Benchmark (for rapid iteration)"
echo "═══════════════════════════════════════"
echo "Testing: rs-bpe, TokenDagger, tiktoken"
echo "Iterations: 100 (vs 1000 in full benchmark)"
echo ""

# Auto-build TokenDagger if needed
TOKENDAGGER_DIR="/Users/steven_chong/downloads/repos/TokenDagger"
if [ -d "$TOKENDAGGER_DIR" ]; then
    if [ ! -f "$TOKENDAGGER_DIR/tokendagger/_tokendagger_core"*.so ]; then
        echo "🔨 Building TokenDagger..."
        cd "$TOKENDAGGER_DIR"
        if [ ! -d "extern/pybind11/include" ]; then
            git submodule update --init --recursive > /dev/null 2>&1
        fi
        g++ -std=c++17 -O2 -fPIC -w \
            -I./src/tiktoken -I./src -I./extern/pybind11/include \
            -I/opt/homebrew/opt/pcre2/include \
            $(python3-config --includes) \
            -shared -undefined dynamic_lookup \
            -o tokendagger/_tokendagger_core.cpython-312-darwin.so \
            src/py_binding.cpp src/tiktoken/libtiktoken.a \
            -L/opt/homebrew/opt/pcre2/lib -lpcre2-8 > /dev/null 2>&1
        cd - > /dev/null
        echo "✅ TokenDagger built"
    fi
fi

[ ! -f benchmark_data.json ] && python3 generate_benchmark_data.py

BENCH_DIR="$(pwd)"

# Create quick benchmark scripts (100 iterations instead of 1000)
cat > /tmp/bench_quick_rsbpe.py <<PYEOF
import json
from rs_bpe.bpe import openai
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
tok = openai.cl100k_base()
for _ in range(100):
    for t in texts: tok.encode(t)
PYEOF

cat > /tmp/bench_quick_tiktoken.py <<PYEOF
import json, tiktoken
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
enc = tiktoken.get_encoding("cl100k_base")
for _ in range(100):
    for t in texts: enc.encode(t)
PYEOF

cat > /tmp/bench_quick_tokendagger.py <<PYEOF
import sys, json, tiktoken as tk
sys.path.insert(0, '/Users/steven_chong/downloads/repos/TokenDagger')
from tokendagger import wrapper
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
tk_enc = tk.get_encoding("cl100k_base")
enc = wrapper.Encoding(
    name="cl100k_base",
    pat_str=tk_enc._pat_str,
    mergeable_ranks=tk_enc._mergeable_ranks,
    special_tokens=tk_enc._special_tokens
)
for _ in range(100):
    for t in texts: enc.encode(t)
PYEOF

echo "Running hyperfine (583 texts × 100 iterations, 3 runs)..."
echo ""

# Run hyperfine with 3 runs instead of 5
hyperfine \
    --warmup 1 \
    --runs 3 \
    --export-markdown bench_quick_results.md \
    --ignore-failure \
    --command-name "rs-bpe" "python3 /tmp/bench_quick_rsbpe.py" \
    --command-name "TokenDagger" "python3 /tmp/bench_quick_tokendagger.py" \
    --command-name "tiktoken" "python3 /tmp/bench_quick_tiktoken.py"

echo ""
echo "📊 Quick results (100 iterations):"
cat bench_quick_results.md
echo ""
echo "💡 For full benchmark (1000 iterations): make benchmark-encoding"
