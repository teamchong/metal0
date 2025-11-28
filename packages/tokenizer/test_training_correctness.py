#!/usr/bin/env python3
"""
Verify 100% correctness of BPE training

Trains tokenizer with metal0, HuggingFace, and compares:
1. Vocab size matches
2. All merge rules are identical
3. Encoding same text produces identical tokens
4. Decoding produces identical text

PASS = 100% identical, FAIL = any difference
"""

import json
import subprocess
import sys
from tokenizers import Tokenizer, models, trainers

# Load training data
with open('benchmark_data.json') as f:
    texts = json.load(f)['texts']

VOCAB_SIZE = 2048
TEST_TEXTS = [
    "The quick brown fox jumps over the lazy dog.",
    "Hello, world! This is a test.",
    "1234567890 !@#$%^&*()",
    "Unicode: 你好世界 🌍🚀",
    texts[0],  # First benchmark text
    texts[100],  # Middle benchmark text
]

print("🔍 BPE Training Correctness Test")
print("=" * 70)
print(f"Training corpus: {len(texts)} texts")
print(f"Vocab size: {VOCAB_SIZE}")
print(f"Test texts: {len(TEST_TEXTS)}")
print()

# Train HuggingFace tokenizer (reference)
print("1️⃣  Training HuggingFace BPE (reference)...")
hf_tokenizer = Tokenizer(models.BPE(unk_token="[UNK]"))
hf_trainer = trainers.BpeTrainer(
    vocab_size=VOCAB_SIZE,
    special_tokens=["[UNK]", "[PAD]"]
)
hf_tokenizer.train_from_iterator(texts, trainer=hf_trainer)
print(f"   ✅ Trained: vocab size = {hf_tokenizer.get_vocab_size()}")

# Save HuggingFace model
hf_tokenizer.save("hf_trained.json")
print()

# Train metal0 tokenizer
print("2️⃣  Training metal0 BPE...")
result = subprocess.run(
    ['./zig-out/bin/bench_train'],
    capture_output=True,
    text=True
)
if result.returncode != 0:
    print(f"   ❌ FAILED: {result.stderr}")
    sys.exit(1)
print(f"   ✅ Trained: {result.stdout.strip()}")
print()

# TODO: metal0 doesn't save trained model yet!
print("⚠️  CRITICAL ISSUE: metal0 training doesn't save the trained model!")
print("   Cannot verify correctness without saved vocab/merges")
print()
print("📋 What we need to verify 100% correctness:")
print("   1. Save trained vocab to JSON")
print("   2. Save merge rules")
print("   3. Compare vocab with HuggingFace")
print("   4. Compare merge order")
print("   5. Encode test texts and compare token IDs")
print()
print("=" * 70)
print("❌ CANNOT VERIFY TRAINING CORRECTNESS - metal0 doesn't expose trained model")
print("=" * 70)
