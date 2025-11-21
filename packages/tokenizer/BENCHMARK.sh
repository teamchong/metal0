#!/bin/bash
# Encoding benchmark using hyperfine (5 libraries with TokenDagger)
# Uses 1000 iterations so Python startup overhead <2%
set -e
cd "$(dirname "$0")"

echo "🚀 Encoding Benchmark (Target: 5 libraries)"
echo "═══════════════════════════════════════════════"
echo ""

# Auto-build TokenDagger if needed
TOKENDAGGER_DIR="/Users/steven_chong/downloads/repos/TokenDagger"
if [ -d "$TOKENDAGGER_DIR" ]; then
    if [ ! -f "$TOKENDAGGER_DIR/tokendagger/_tokendagger_core"*.so ]; then
        echo "🔨 Auto-building TokenDagger..."
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
        if [ $? -eq 0 ]; then
            echo "   ✅ TokenDagger built successfully"
        else
            echo "   ⚠️  TokenDagger build failed (will skip)"
        fi
        cd - > /dev/null
    else
        echo "✅ TokenDagger already built"
    fi
fi

[ ! -f benchmark_data.json ] && python3 generate_benchmark_data.py

BENCH_DIR="$(pwd)"
echo ""
echo "Creating benchmark scripts..."

# 1. rs-bpe
cat > /tmp/bench_enc_rsbpe.py <<PYEOF
import json
from rs_bpe.bpe import openai
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
tok = openai.cl100k_base()
for _ in range(1000):
    for t in texts: tok.encode(t)
PYEOF

# 2. tiktoken
cat > /tmp/bench_enc_tiktoken.py <<PYEOF
import json, tiktoken
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
enc = tiktoken.get_encoding("cl100k_base")
for _ in range(1000):
    for t in texts: enc.encode(t)
PYEOF

# 3. TokenDagger
cat > /tmp/bench_enc_tokendagger.py <<PYEOF
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
for _ in range(1000):
    for t in texts: enc.encode(t)
PYEOF

# 4. HuggingFace
cat > /tmp/bench_enc_hf.py <<PYEOF
import json, warnings
warnings.filterwarnings('ignore')
from transformers import GPT2TokenizerFast
texts = json.load(open('${BENCH_DIR}/benchmark_data.json'))['texts']
tok = GPT2TokenizerFast.from_pretrained('gpt2')
for _ in range(1000):
    for t in texts: tok.encode(t)
PYEOF

echo ""
echo "Running hyperfine benchmark (583 texts × 1000 iterations per run)..."
echo "Note: Python startup overhead <2% with 1000 iterations"
echo ""

# Run hyperfine with explicit commands
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_encoding_results.md \
    --ignore-failure \
    --command-name "rs-bpe" "python3 /tmp/bench_enc_rsbpe.py" \
    --command-name "tiktoken" "python3 /tmp/bench_enc_tiktoken.py" \
    --command-name "TokenDagger" "python3 /tmp/bench_enc_tokendagger.py" \
    --command-name "HuggingFace" "python3 /tmp/bench_enc_hf.py"

echo ""
echo "📊 Results saved to bench_encoding_results.md"
echo ""
cat bench_encoding_results.md
