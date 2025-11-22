#!/bin/bash
# Universal tokenizer benchmark - handles failures gracefully
# Works on any machine, no hardcoded paths

set -e

echo "🚀 Universal Tokenizer Benchmark"
echo "════════════════════════════════════════"
echo ""

# Check benchmark data
if [ ! -f benchmark_data.json ]; then
    echo "Generating benchmark data..."
    python3 generate_benchmark_data.py
fi

# Count texts
NTEXTS=$(python3 -c "import json; print(len(json.load(open('benchmark_data.json'))['texts']))")
echo "Dataset: $NTEXTS texts × 100 iterations"
echo ""

# Test and create benchmark scripts
AVAILABLE=()

# rs-bpe
if python3 -c "from rs_bpe.bpe import openai; openai.cl100k_base()" 2>/dev/null; then
    cat > /tmp/b_rsbpe.py << 'EOF'
import time, json
from rs_bpe.bpe import openai
texts = json.load(open('benchmark_data.json'))['texts']
tok = openai.cl100k_base()
for t in texts[:5]: tok.encode(t)
s = time.time()
for _ in range(100):
    for t in texts: tok.encode(t)
print(f"{(time.time()-s)*1000:.0f}ms")
EOF
    AVAILABLE+=("rs-bpe:::python3 /tmp/b_rsbpe.py")
    echo "✅ rs-bpe"
else
    echo "❌ rs-bpe (pip install rs-bpe)"
fi

# tiktoken
if python3 -c "import tiktoken; tiktoken.get_encoding('cl100k_base').encode('test')" 2>/dev/null; then
    cat > /tmp/b_tiktoken.py << 'EOF'
import time, json, tiktoken
texts = json.load(open('benchmark_data.json'))['texts']
enc = tiktoken.get_encoding("cl100k_base")
for t in texts[:5]: enc.encode(t)
s = time.time()
for _ in range(100):
    for t in texts: enc.encode(t)
print(f"{(time.time()-s)*1000:.0f}ms")
EOF
    AVAILABLE+=("tiktoken:::python3 /tmp/b_tiktoken.py")
    echo "✅ tiktoken"
else
    echo "❌ tiktoken (pip install tiktoken)"
fi

# HuggingFace
if python3 -c "from transformers import GPT2TokenizerFast; GPT2TokenizerFast.from_pretrained('gpt2').encode('test')" 2>/dev/null; then
    cat > /tmp/b_hf.py << 'EOF'
import time, json
from transformers import GPT2TokenizerFast
texts = json.load(open('benchmark_data.json'))['texts']
tok = GPT2TokenizerFast.from_pretrained('gpt2')
for t in texts[:5]: tok.encode(t)
s = time.time()
for _ in range(100):
    for t in texts: tok.encode(t)
print(f"{(time.time()-s)*1000:.0f}ms")
EOF
    AVAILABLE+=("HuggingFace:::python3 /tmp/b_hf.py")
    echo "✅ HuggingFace"
else
    echo "❌ HuggingFace (pip install transformers)"
fi

# Build hyperfine command
if [ ${#AVAILABLE[@]} -eq 0 ]; then
    echo ""
    echo "❌ No tokenizers available!"
    echo "   Install: pip install rs-bpe tiktoken transformers"
    exit 1
fi

echo ""
echo "Running benchmark..."
echo ""

HFARGS=()
for lib in "${AVAILABLE[@]}"; do
    IFS=':::' read -r name cmd <<< "$lib"
    HFARGS+=("--command-name" "$name" "$cmd")
done

hyperfine --warmup 1 --runs 5 --export-markdown bench_results.md "${HFARGS[@]}"

echo ""
echo "📊 Results saved to bench_results.md"
echo ""
cat bench_results.md
