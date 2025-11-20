#!/bin/bash
# Hyperfine benchmark: Encoding (all libraries, realistic data)

set -e

echo "⚡ Encoding Benchmark: All Libraries (realistic corpus)"
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

# Create rs-bpe benchmark
cat > /tmp/bench_rsbpe_enc.py << 'PYEOF'
import time, json
from rs_bpe.bpe import openai

with open('benchmark_data.json') as f:
    texts = json.load(f)['texts']

tokenizer = openai.cl100k_base()

# Warmup
for text in texts[:10]:
    tokenizer.encode(text)

# Benchmark: encode all texts 100 times
start = time.time()
for _ in range(100):
    for text in texts:
        tokenizer.encode(text)
elapsed = time.time() - start

print(f"{int(elapsed * 1000)}ms")
PYEOF

# Create tiktoken benchmark
cat > /tmp/bench_tiktoken_enc.py << 'PYEOF'
import time, tiktoken, json

with open('benchmark_data.json') as f:
    texts = json.load(f)['texts']

enc = tiktoken.get_encoding("cl100k_base")

# Warmup
for text in texts[:10]:
    enc.encode(text)

# Benchmark: encode all texts 100 times
start = time.time()
for _ in range(100):
    for text in texts:
        enc.encode(text)
elapsed = time.time() - start

print(f"{int(elapsed * 1000)}ms")
PYEOF

# Create HuggingFace benchmark
cat > /tmp/bench_hf_enc.py << 'PYEOF'
import time, json
from transformers import GPT2TokenizerFast

with open('benchmark_data.json') as f:
    texts = json.load(f)['texts']

tokenizer = GPT2TokenizerFast.from_pretrained('gpt2')

# Warmup
for text in texts[:10]:
    tokenizer.encode(text)

# Benchmark
start = time.time()
for _ in range(100):
    for text in texts:
        tokenizer.encode(text)
elapsed = time.time() - start

print(f"{int(elapsed * 1000)}ms")
PYEOF

# Run hyperfine (SKIP PyAOT - currently too slow)
echo "⚠️  Skipping PyAOT native - currently too slow"
echo ""

hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_encoding_results.md \
    --command-name "rs-bpe (Rust)" 'python3 /tmp/bench_rsbpe_enc.py' \
    --command-name "tiktoken (Rust)" 'python3 /tmp/bench_tiktoken_enc.py' \
    --command-name "HuggingFace (Python)" 'python3 /tmp/bench_hf_enc.py'

echo ""
echo "📊 Results saved to bench_encoding_results.md"
