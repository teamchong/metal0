#!/usr/bin/env python3
"""Compare metal0 vs HuggingFace BPE training"""
import subprocess
import re
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer
from tokenizers.pre_tokenizers import ByteLevel

# Same training corpus
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

hf_vocab = tokenizer.get_vocab()
hf_tokens = set(hf_vocab.keys())

print("=== HuggingFace Training ===")
print(f"Vocab size: {len(hf_vocab)}")

# Parse metal0 output
result = subprocess.run(['./zig-out/bin/test_training'], capture_output=True, timeout=30)
output = result.stderr.decode('utf-8')

metal0_tokens = set()
for line in output.split('\n'):
    if ": '" in line and line.strip().endswith("'"):
        # Extract token between quotes
        start = line.index("'") + 1
        end = line.rindex("'")
        token_str = line[start:end]
        # Convert \xNN sequences to bytes, then decode as UTF-8
        # First collect all bytes, then decode
        result_bytes = []
        i = 0
        while i < len(token_str):
            if token_str[i:i+2] == '\\x' and i + 3 < len(token_str):
                hex_str = token_str[i+2:i+4]
                try:
                    result_bytes.append(int(hex_str, 16))
                    i += 4
                except ValueError:
                    result_bytes.append(ord(token_str[i]))
                    i += 1
            else:
                result_bytes.append(ord(token_str[i]))
                i += 1
        token = bytes(result_bytes).decode('utf-8', errors='replace')
        metal0_tokens.add(token)

print(f"\n=== metal0 Training ===")
print(f"Vocab tokens: {len(metal0_tokens)}")

# Compare
common = hf_tokens & metal0_tokens
hf_only = hf_tokens - metal0_tokens
metal0_only = metal0_tokens - hf_tokens

print(f"\n=== Comparison ===")
print(f"Common tokens: {len(common)}")
print(f"HF-only tokens: {len(hf_only)}")
print(f"metal0-only tokens: {len(metal0_only)}")

# Show differences
if hf_only:
    print(f"\n=== HF-only tokens ({len(hf_only)}) ===")
    for t in sorted(hf_only, key=lambda x: (len(x), x))[:40]:
        print(f"  {repr(t)}")
    if len(hf_only) > 40:
        print(f"  ... ({len(hf_only)-40} more)")

if metal0_only:
    print(f"\n=== metal0-only tokens ({len(metal0_only)}) ===")
    for t in sorted(metal0_only, key=lambda x: (len(x), x))[:40]:
        print(f"  {repr(t)}")
    if len(metal0_only) > 40:
        print(f"  ... ({len(metal0_only)-40} more)")

# Calculate match percentage
if len(hf_tokens) > 0:
    match_pct = len(common) / len(hf_tokens) * 100
    print(f"\n=== Match: {match_pct:.1f}% ({len(common)}/{len(hf_tokens)}) ===")
