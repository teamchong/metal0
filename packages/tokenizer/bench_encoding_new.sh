#!/bin/bash
# Auto-benchmark ALL available tokenizers
# No hardcoded paths - works anywhere

set -e

echo "⚡ Tokenizer Benchmark (all available libraries)"
echo "═══════════════════════════════════════════════════"
echo "Encoding: 583 diverse texts × 100 iterations"
echo ""

# Generate data if needed
[ ! -f benchmark_data.json ] && python3 generate_benchmark_data.py

# Test which libraries work
echo "Detecting available tokenizers..."
BENCHMARKS=()

# rs-bpe
if python3 -c "from rs_bpe.bpe import openai" 2>/dev/null; then
    cat > /tmp/bench_rsbpe.py << 'EOF'
import time, json
from rs_bpe.bpe import openai
with open('benchmark_data.json') as f: texts = json.load(f)['texts']
tok = openai.cl100k_base()
[tok.encode(t) for t in texts[:10]]  # Warmup
start = time.time()
for _ in range(100): [tok.encode(t) for t in texts]
print(f"{int((time.time()-start)*1000)}ms")
EOF
    BENCHMARKS+=("--command-name" "rs-bpe" "python3 /tmp/bench_rsbpe.py")
    echo "  ✅ rs-bpe"
else
    echo "  ❌ rs-bpe (pip install rs-bpe)"
fi

# tiktoken
if python3 -c "import tiktoken" 2>/dev/null; then
    cat > /tmp/bench_tiktoken.py << 'EOF'
import time, json, tiktoken
with open('benchmark_data.json') as f: texts = json.load(f)['texts']
enc = tiktoken.get_encoding("cl100k_base")
[enc.encode(t) for t in texts[:10]]  # Warmup
start = time.time()
for _ in range(100): [enc.encode(t) for t in texts]
print(f"{int((time.time()-start)*1000)}ms")
EOF
    BENCHMARKS+=("--command-name" "tiktoken" "python3 /tmp/bench_tiktoken.py")
    echo "  ✅ tiktoken"
else
    echo "  ❌ tiktoken (pip install tiktoken)"
fi

# TokenDagger
if python3 -c "import tokendagger" 2>/dev/null; then
    cat > /tmp/bench_tokendagger.py << 'EOF'
import time, json, tokendagger as tiktoken
with open('benchmark_data.json') as f: texts = json.load(f)['texts']
enc = tiktoken.Encoding.cl100k_base()
[enc.encode(t) for t in texts[:10]]  # Warmup
start = time.time()
for _ in range(100): [enc.encode(t) for t in texts]
print(f"{int((time.time()-start)*1000)}ms")
EOF
    BENCHMARKS+=("--command-name" "TokenDagger" "python3 /tmp/bench_tokendagger.py")
    echo "  ✅ TokenDagger"
else
    echo "  ❌ TokenDagger (see setup_benchmark.sh)"
fi

# HuggingFace
if python3 -c "from transformers import GPT2TokenizerFast" 2>/dev/null; then
    cat > /tmp/bench_hf.py << 'EOF'
import time, json
from transformers import GPT2TokenizerFast
with open('benchmark_data.json') as f: texts = json.load(f)['texts']
tok = GPT2TokenizerFast.from_pretrained('gpt2')
[tok.encode(t) for t in texts[:10]]  # Warmup
start = time.time()
for _ in range(100): [tok.encode(t) for t in texts]
print(f"{int((time.time()-start)*1000)}ms")
EOF
    BENCHMARKS+=("--command-name" "HuggingFace" "python3 /tmp/bench_hf.py")
    echo "  ✅ HuggingFace"
else
    echo "  ❌ HuggingFace (pip install transformers)"
fi

# Run benchmark
if [ ${#BENCHMARKS[@]} -eq 0 ]; then
    echo ""
    echo "❌ No tokenizers available! Run: ./setup_benchmark.sh"
    exit 1
fi

echo ""
echo "Benchmarking ${#BENCHMARKS[@]} tokenizers..."
echo ""

hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_results.md \
    "${BENCHMARKS[@]}"

echo ""
echo "📊 Results:"
cat bench_results.md
