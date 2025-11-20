#!/bin/bash
# Hyperfine benchmark: BPE Training (PyAOT vs HuggingFace vs SentencePiece)

set -e

echo "⚡ BPE Training Benchmark (hyperfine)"
echo "============================================================"
echo "Training: 583 diverse texts (200K chars), vocab 2048"
echo "Following industry standards: realistic diverse corpus"
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
import time, json
from tokenizers import Tokenizer, models, trainers

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

VOCAB_SIZE = 2048

tokenizer = Tokenizer(models.BPE(unk_token="[UNK]"))
trainer = trainers.BpeTrainer(
    vocab_size=VOCAB_SIZE,
    special_tokens=["[UNK]", "[PAD]"]
)

start = time.time()
tokenizer.train_from_iterator(texts, trainer=trainer)
elapsed = time.time() - start

print(f"{int(elapsed * 1000)}ms")
PYEOF

cat > /tmp/bench_spm_train.py << 'PYEOF'
import time, json
import sentencepiece as spm
import tempfile
import os

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

# Write training data
with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
    for text in texts:
        f.write(text + "\n")
    temp_file = f.name

# Train
start = time.time()
spm.SentencePieceTrainer.train(
    input=temp_file,
    model_prefix='temp_spm',
    vocab_size=100,  # BPE mode limit
    model_type='bpe'
)
elapsed = time.time() - start

# Cleanup
os.unlink(temp_file)
if os.path.exists('temp_spm.model'):
    os.unlink('temp_spm.model')
if os.path.exists('temp_spm.vocab'):
    os.unlink('temp_spm.vocab')

print(f"{int(elapsed * 1000)}ms")
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
