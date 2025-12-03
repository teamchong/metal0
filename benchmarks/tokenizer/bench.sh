#!/bin/bash
# Tokenizer Benchmark - metal0 BPE vs tiktoken vs rs-bpe vs HuggingFace
# Tests BPE encoding performance on realistic text data

source "$(dirname "$0")/../common.sh"

TOKENIZER_PKG="$PROJECT_ROOT/packages/tokenizer"

init_benchmark "Tokenizer Benchmark"
echo ""
echo "BPE encoding (cl100k_base compatible)"
echo ""

# Check if tokenizer package exists
if [ ! -d "$TOKENIZER_PKG" ]; then
    echo -e "${RED}Error: packages/tokenizer not found${NC}"
    exit 1
fi

cd "$TOKENIZER_PKG"

# Check benchmark data
if [ ! -f benchmark_data.json ]; then
    echo "Generating benchmark data..."
    python3 generate_benchmark_data.py
fi

# Count texts
NTEXTS=$(python3 -c "import json; print(len(json.load(open('benchmark_data.json'))['texts']))")
echo "Dataset: $NTEXTS texts x 100 iterations"
echo ""

# Build metal0 compiler
echo "Building..."
build_metal0_compiler

# Compile and run metal0 Python benchmark (shown separately due to cache bug)
METAL0_TIME=""
if [ -f "$SCRIPT_DIR/bench_metal0.py" ]; then
    cp "$SCRIPT_DIR/bench_metal0.py" "$TOKENIZER_PKG/"
    cd "$PROJECT_ROOT"
    # Run metal0 benchmark with --force (cache has argv bug)
    echo "Running metal0 benchmark (separate from hyperfine due to compilation)..."
    METAL0_OUTPUT=$(./zig-out/bin/metal0 "$TOKENIZER_PKG/bench_metal0.py" --force 2>&1)
    if [ $? -eq 0 ]; then
        METAL0_TIME=$(echo "$METAL0_OUTPUT" | grep -oE '[0-9]+\.[0-9]+ ms' | head -1)
        echo -e "  ${GREEN}✓${NC} metal0: $METAL0_TIME"
    else
        echo -e "  ${YELLOW}⚠${NC} metal0 failed (will skip)"
        echo "$METAL0_OUTPUT" | tail -5
    fi
fi

cd "$TOKENIZER_PKG"

# Build benchmark commands (metal0 shown separately)
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
    echo -e "${GREEN}✓${NC} rs-bpe"
else
    echo -e "${YELLOW}⚠${NC} rs-bpe (pip install rs-bpe)"
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
    echo -e "${GREEN}✓${NC} tiktoken"
else
    echo -e "${YELLOW}⚠${NC} tiktoken (pip install tiktoken)"
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
    echo -e "${GREEN}✓${NC} HuggingFace"
else
    echo -e "${YELLOW}⚠${NC} HuggingFace (pip install transformers)"
fi

# Build hyperfine command
if [ ${#AVAILABLE[@]} -eq 0 ]; then
    echo ""
    echo -e "${RED}No tokenizers available!${NC}"
    echo "   Install: pip install rs-bpe tiktoken transformers"
    exit 1
fi

echo ""
echo "Running benchmark..."
echo ""

HFARGS=()
for lib in "${AVAILABLE[@]}"; do
    # Use pattern matching instead of IFS (IFS doesn't handle multi-char delimiters)
    name="${lib%%:::*}"
    cmd="${lib#*:::}"
    HFARGS+=("--command-name" "$name" "$cmd")
done

hyperfine --warmup 1 --runs 5 --export-markdown bench_results.md "${HFARGS[@]}"

echo ""
echo "Results saved to bench_results.md"
echo ""
cat bench_results.md

# Cleanup
rm -f "$TOKENIZER_PKG/bench_metal0.py" "$TOKENIZER_PKG/bench_metal0_bin" 2>/dev/null
