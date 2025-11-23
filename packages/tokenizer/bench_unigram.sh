#!/bin/bash
# Hyperfine benchmark: Unigram Training (PyAOT vs HuggingFace vs SentencePiece)

set -e

echo "⚡ Unigram Training Benchmark (hyperfine)"
echo "============================================================"
echo "Training: 583 texts × 300 iterations"
echo "PyAOT/HF: vocab 32000 | SentencePiece: vocab 32000"
echo "Python startup overhead ~0.2% with 300 training runs"
echo ""

# Generate benchmark data if needed
if [ ! -f benchmark_data.json ]; then
    echo "Generating realistic benchmark data..."
    python3 generate_benchmark_data.py
    echo ""
fi

# Build bench_train (all algorithms included, dead code elimination handles unused code)
echo "Building trainer..."
zig build -Doptimize=ReleaseFast

cat > /tmp/bench_hf_unigram.py << 'PYEOF'
import json
from tokenizers import Tokenizer, models, trainers

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

VOCAB_SIZE = 32000

# Train 300 times to amortize Python startup overhead
for _ in range(300):
    tokenizer = Tokenizer(models.Unigram())
    trainer = trainers.UnigramTrainer(
        vocab_size=VOCAB_SIZE,
        special_tokens=["[UNK]", "[PAD]"]
    )
    tokenizer.train_from_iterator(texts, trainer=trainer)
PYEOF

cat > /tmp/bench_spm_unigram.py << 'PYEOF'
import json
import sentencepiece as spm
import tempfile
import os

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

# Write training data once
with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
    for text in texts:
        f.write(text + "\n")
    temp_file = f.name

# Train 300 times to amortize Python startup overhead
for i in range(300):
    spm.SentencePieceTrainer.train(
        input=temp_file,
        model_prefix=f'temp_spm_{i}',
        vocab_size=32000,
        model_type='unigram',
        minloglevel=2  # Suppress logs
    )
    # Cleanup immediately
    if os.path.exists(f'temp_spm_{i}.model'):
        os.unlink(f'temp_spm_{i}.model')
    if os.path.exists(f'temp_spm_{i}.vocab'):
        os.unlink(f'temp_spm_{i}.vocab')

# Cleanup temp file
os.unlink(temp_file)
PYEOF

# Run hyperfine (use ALGORITHM env var to select Unigram)
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_unigram_results.md \
    --command-name "PyAOT (Zig)" 'ALGORITHM=Unigram ./zig-out/bin/bench_train' \
    --command-name "HuggingFace (Rust)" 'python3 /tmp/bench_hf_unigram.py' \
    --command-name "SentencePiece (C++)" 'python3 /tmp/bench_spm_unigram.py'

echo ""
echo "📊 Results saved to bench_unigram_results.md"
