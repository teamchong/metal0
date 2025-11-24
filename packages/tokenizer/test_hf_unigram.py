#!/usr/bin/env python3
"""Test HuggingFace Unigram trainer with our benchmark data."""
import json
from tokenizers import Tokenizer, models, trainers

# Load our benchmark data
with open('benchmark_data.json') as f:
    data = json.load(f)
    texts = data['texts']

print(f"Loaded {len(texts)} texts, total chars: {sum(len(t) for t in texts)}")
print(f"First text (50 chars): {texts[0][:50]}...")
print(f"Concatenated hash: {__import__('hashlib').sha256(''.join(texts).encode()).hexdigest()[:16]}")

# Create Unigram model (minimal vocab - trainer will replace)
tokenizer = Tokenizer(models.Unigram(vocab=[("<UNK>", 0.0)], unk_id=0, byte_fallback=False))

# Check if tokenizer has normalizer or pre_tokenizer
print(f"\n=== TOKENIZER PIPELINE ===")
print(f"Normalizer: {tokenizer.normalizer}")
print(f"Pre-tokenizer: {tokenizer.pre_tokenizer}")
print(f"Decoder: {tokenizer.decoder}")

# Create trainer with EXPLICIT config (all defaults visible)
trainer = trainers.UnigramTrainer(
    vocab_size=32000,
    show_progress=True,
    unk_token="<UNK>",
    max_piece_length=16,  # Default
    shrinking_factor=0.75,  # Default
    n_sub_iterations=2,  # Default
)

# Print all trainer attributes for debugging
print("\n=== TRAINER CONFIG ===")
print(f"vocab_size: 32000")
print(f"max_piece_length: 16")
print(f"shrinking_factor: 0.75")
print(f"n_sub_iterations: 2")

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
