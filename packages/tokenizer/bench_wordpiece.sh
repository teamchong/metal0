#!/bin/bash
# Hyperfine benchmark: WordPiece Training (PyAOT vs HuggingFace)

set -e

echo "⚡ WordPiece Training Benchmark (hyperfine)"
echo "============================================================"
echo "Training: 583 texts × 300 iterations"
echo "PyAOT/HF: vocab 32000"
echo "Note: SentencePiece doesn't support WordPiece"
echo ""

# Generate benchmark data if needed
if [ ! -f benchmark_data.json ]; then
    echo "Generating realistic benchmark data..."
    python3 generate_benchmark_data.py
    echo ""
fi

# Build bench_train for WordPiece using build.zig
echo "Building WordPiece trainer..."
zig build -Dinclude_bpe=false -Dinclude_wordpiece=true -Dinclude_unigram=false -Doptimize=ReleaseFast

cat > /tmp/bench_hf_wordpiece.py << 'PYEOF'
import json
from tokenizers import Tokenizer, models, trainers

# Load realistic benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

VOCAB_SIZE = 32000

# Train 300 times to amortize Python startup overhead
for _ in range(300):
    tokenizer = Tokenizer(models.WordPiece(unk_token="[UNK]"))
    trainer = trainers.WordPieceTrainer(
        vocab_size=VOCAB_SIZE,
        special_tokens=["[UNK]", "[PAD]"]
    )
    tokenizer.train_from_iterator(texts, trainer=trainer)
PYEOF

# Run hyperfine
hyperfine \
    --warmup 1 \
    --runs 5 \
    --export-markdown bench_wordpiece_results.md \
    --command-name "PyAOT (Zig)" './zig-out/bin/bench_train' \
    --command-name "HuggingFace (Rust)" 'python3 /tmp/bench_hf_wordpiece.py'

echo ""
echo "📊 Results saved to bench_wordpiece_results.md"
