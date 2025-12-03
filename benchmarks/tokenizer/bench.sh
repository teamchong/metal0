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

# Compile metal0 Python benchmark
cd "$SCRIPT_DIR"
if [ -f "bench_metal0.py" ]; then
    cp "$SCRIPT_DIR/bench_metal0.py" "$TOKENIZER_PKG/"
    cd "$PROJECT_ROOT"
    if ./zig-out/bin/metal0 "$TOKENIZER_PKG/bench_metal0.py" --force -o "$TOKENIZER_PKG/bench_metal0_bin" 2>/dev/null; then
        METAL0_BIN="$TOKENIZER_PKG/bench_metal0_bin"
        echo -e "  ${GREEN}✓${NC} metal0 tokenizer"
    else
        echo -e "  ${YELLOW}⚠${NC} metal0 compile failed (will skip)"
        METAL0_BIN=""
    fi
fi

cd "$TOKENIZER_PKG"

# Build benchmark commands
AVAILABLE=()

# metal0 (compiled Python using native tokenizer)
if [ -n "$METAL0_BIN" ] && [ -f "$METAL0_BIN" ]; then
    AVAILABLE+=("metal0:::$METAL0_BIN")
    echo -e "${GREEN}✓${NC} metal0"
fi

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
    IFS=':::' read -r name cmd <<< "$lib"
    HFARGS+=("--command-name" "$name" "$cmd")
done

hyperfine --warmup 1 --runs 5 --export-markdown bench_results.md "${HFARGS[@]}"

echo ""
echo "Results saved to bench_results.md"
echo ""
cat bench_results.md

# Cleanup
rm -f "$TOKENIZER_PKG/bench_metal0.py" "$TOKENIZER_PKG/bench_metal0_bin" 2>/dev/null
