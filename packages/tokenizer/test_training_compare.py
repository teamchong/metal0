#!/usr/bin/env python3
"""Compare metal0 training vs HuggingFace training"""
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import ByteLevel

# Training corpus
texts = [
    "Hello world! How are you doing today?",
    "The quick brown fox jumps over the lazy dog.",
    "Machine learning is transforming technology.",
    "Python is a popular programming language.",
    "The weather is nice today, isn't it?",
]

# Train with HuggingFace
tokenizer = Tokenizer(BPE())
tokenizer.pre_tokenizer = ByteLevel(add_prefix_space=False)
trainer = BpeTrainer(vocab_size=200, min_frequency=1, show_progress=False)
tokenizer.train_from_iterator(texts, trainer=trainer)

print("=== HuggingFace Trained Vocab ===")
vocab = tokenizer.get_vocab()
print(f"Vocab size: {len(vocab)}")

# Sort by token id
sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])

# Show first 50 tokens (base chars) and merged tokens
base_tokens = [t for t, i in sorted_vocab if len(t) <= 2]
merged_tokens = [t for t, i in sorted_vocab if len(t) > 2]

print(f"\nBase tokens ({len(base_tokens)}): {base_tokens[:30]}...")
print(f"\nMerged tokens ({len(merged_tokens)}):")
for t, i in sorted_vocab:
    if len(t) > 2:
        print(f"  {i}: {repr(t)}")
