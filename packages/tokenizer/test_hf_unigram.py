#!/usr/bin/env python3
"""Test HuggingFace Unigram trainer with our benchmark data."""
import json
from tokenizers import Tokenizer, models, trainers

# Load our benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

print(f"Loaded {len(texts)} texts, total chars: {sum(len(t) for t in texts)}")

# Create Unigram model (minimal vocab - trainer will replace)
tokenizer = Tokenizer(models.Unigram(vocab=[("<UNK>", 0.0)], unk_id=0, byte_fallback=False))

# Create trainer with same config as PyAOT
trainer = trainers.UnigramTrainer(
    vocab_size=32000,
    show_progress=True,
    unk_token="<UNK>",
)

# Train with verbose output
import sys
print("\nTraining HuggingFace Unigram tokenizer...", file=sys.stderr)
tokenizer.train_from_iterator(texts, trainer=trainer)
print("Training complete!", file=sys.stderr)

# Check vocab size
vocab = tokenizer.get_vocab()
print(f"\nFinal vocab size: {len(vocab)}")
print(f"First 20 tokens: {list(vocab.keys())[:20]}")

# Save for comparison
tokenizer.save("hf_benchmark_trained.json")
print("\nSaved to hf_benchmark_trained.json")
