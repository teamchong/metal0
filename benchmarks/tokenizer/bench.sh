#!/bin/bash
# Tokenizer Benchmark - PyAOT BPE vs tiktoken vs rs-bpe vs HuggingFace
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
echo "Dataset: $NTEXTS texts × 100 iterations"
echo ""

# Run the main benchmark script
if [ -f "benchmark_all.sh" ]; then
    bash benchmark_all.sh
else
    echo -e "${RED}Error: benchmark_all.sh not found in packages/tokenizer${NC}"
    exit 1
fi
