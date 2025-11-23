#!/bin/bash
# Hyperfine benchmark: BPE Training (PyAOT vs HuggingFace vs SentencePiece)

set -e

echo "⚡ BPE Training Benchmark (hyperfine)"
echo "============================================================"
echo "Training: 583 texts × 30 iterations"
echo "PyAOT/HF: vocab 32000 | SentencePiece: vocab 2066 (BPE max)"
echo "Python startup overhead ~2% with 30 training runs"
echo ""

# Generate benchmark data if needed
if [ ! -f benchmark_data.json ]; then
    echo "Generating realistic benchmark data..."
    python3 generate_benchmark_data.py
    echo ""
fi

# Build bench_train if needed
if [ ! -f zig-out/bin/bench_train ]; then
    echo "Building bench_train..."
    zig build-exe src/bench_train.zig -O ReleaseFast
    mv bench_train zig-out/bin/
fi

cat > /tmp/bench_hf_train.py << 'PYEOF'
import json
from tokenizers import Tokenizer, models, trainers

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

VOCAB_SIZE = 32000

# Train 30 times to amortize Python startup overhead
for _ in range(30):
    tokenizer = Tokenizer(models.BPE(unk_token="[UNK]"))
    trainer = trainers.BpeTrainer(
        vocab_size=VOCAB_SIZE,
        special_tokens=["[UNK]", "[PAD]"]
    )
    tokenizer.train_from_iterator(texts, trainer=trainer)
PYEOF

cat > /tmp/bench_spm_train.py << 'PYEOF'
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

# Train 30 times to amortize Python startup overhead
# SentencePiece BPE max vocab for this corpus: 2066
for i in range(30):
    spm.SentencePieceTrainer.train(
        input=temp_file,
        model_prefix=f'temp_spm_{i}',
        vocab_size=2066,  # Maximum for this corpus
        model_type='bpe',
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

# Run hyperfine
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_training_results.md \
    --command-name "PyAOT (Zig)" './zig-out/bin/bench_train' \
    --command-name "HuggingFace (Rust)" 'python3 /tmp/bench_hf_train.py' \
    --command-name "SentencePiece (C++)" 'python3 /tmp/bench_spm_train.py'

echo ""
echo "📊 Results saved to bench_training_results.md"
