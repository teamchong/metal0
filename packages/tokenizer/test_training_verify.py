#!/usr/bin/env python3
"""100% Training Correctness Verification - metal0 vs HuggingFace"""

import json
import subprocess
from tokenizers import Tokenizer
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer

print("🔍 100% Training Correctness Verification")
print("=" * 70)
print()

VOCAB_SIZE = 2048

# Load benchmark data
with open("benchmark_data.json") as f:
    data = json.load(f)
    corpus = data["texts"]

print(f"Training corpus: {len(corpus)} texts")
print(f"Vocab size: {VOCAB_SIZE}")
print()

#  1. Train with HuggingFace (reference)
print("1️⃣  Training HuggingFace BPE (reference)...")
hf_tokenizer = Tokenizer(BPE())
trainer = BpeTrainer(vocab_size=VOCAB_SIZE, special_tokens=[])
hf_tokenizer.train_from_iterator(corpus, trainer=trainer)
hf_tokenizer.save("hf_trained.json")
print("   ✅ Saved to hf_trained.json")
print()

# 2. Train with metal0
print("2️⃣  Training metal0 BPE...")
result = subprocess.run(
    ["./zig-out/bin/bench_train"],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    print(f"   ❌ metal0 training failed!")
    print(f"   Error: {result.stderr}")
    exit(1)

print(f"   ✅ Training time: {result.stdout.strip()}")
print(f"   ✅ Saved to metal0_trained.json")
print()

# 3. Load both models
print("3️⃣  Loading trained models...")
with open("hf_trained.json") as f:
    hf_model = json.load(f)

with open("metal0_trained.json") as f:
    metal0_model = json.load(f)

print("   ✅ Both models loaded")
print()

# 4. Compare vocab
print("4️⃣  Comparing vocabularies...")
hf_vocab = hf_model["model"]["vocab"]
metal0_vocab = metal0_model["model"]["vocab"]

print(f"   HuggingFace vocab size: {len(hf_vocab)}")
print(f"   metal0 vocab size: {len(metal0_vocab)}")

vocab_match = set(hf_vocab.keys()) == set(metal0_vocab.keys())
if vocab_match:
    # Also check IDs match
    id_match = all(hf_vocab.get(k) == metal0_vocab.get(k) for k in hf_vocab.keys())
    if id_match:
        print("   ✅ Vocab 100% MATCH!")
    else:
        print("   ⚠️  Vocab tokens match but IDs differ")
        vocab_match = False
else:
    print("   ❌ Vocab MISMATCH!")
    hf_only = set(hf_vocab.keys()) - set(metal0_vocab.keys())
    metal0_only = set(metal0_vocab.keys()) - set(hf_vocab.keys())
    if hf_only:
        print(f"      HF-only tokens: {len(hf_only)}")
    if metal0_only:
        print(f"      metal0-only tokens: {len(metal0_only)}")

print()

# 5. Compare merges
print("5️⃣  Comparing merge rules...")
hf_merges = hf_model["model"]["merges"]
metal0_merges = metal0_model["model"]["merges"]

print(f"   HuggingFace merges: {len(hf_merges)}")
print(f"   metal0 merges: {len(metal0_merges)}")

if len(hf_merges) != len(metal0_merges):
    print("   ❌ Different number of merges!")
    merges_match = False
else:
    # Check if merge order matches
    merges_match = hf_merges == metal0_merges
    if merges_match:
        print("   ✅ Merges 100% MATCH (order preserved)!")
    else:
        # Count how many match
        matches = sum(1 for i in range(len(hf_merges)) if hf_merges[i] == metal0_merges[i])
        print(f"   ⚠️  Merges differ: {matches}/{len(hf_merges)} match")
        merges_match = False

print()

# 6. Test encoding
print("6️⃣  Testing encoding with trained models...")
test_texts = [
    "Hello, world!",
    "The quick brown fox",
    "GPT-4 is awesome! 🎉"
]

hf_enc = Tokenizer.from_file("hf_trained.json")
metal0_enc = Tokenizer.from_file("metal0_trained.json")

encoding_match = True
for text in test_texts:
    hf_tokens = hf_enc.encode(text).ids
    metal0_tokens = metal0_enc.encode(text).ids

    if hf_tokens == metal0_tokens:
        print(f"   ✅ '{text[:30]}...' - tokens match")
    else:
        print(f"   ❌ '{text[:30]}...' - tokens DIFFER!")
        print(f"      HF: {hf_tokens}")
        print(f"      metal0: {metal0_tokens}")
        encoding_match = False

print()

# Final verdict
print("=" * 70)
if vocab_match and merges_match and encoding_match:
    print("🎉 100% CORRECT! metal0 training matches HuggingFace perfectly!")
    print("=" * 70)
    exit(0)
else:
    print("❌ VERIFICATION FAILED!")
    print(f"   Vocab: {'✅' if vocab_match else '❌'}")
    print(f"   Merges: {'✅' if merges_match else '❌'}")
    print(f"   Encoding: {'✅' if encoding_match else '❌'}")
    print("=" * 70)
    exit(1)
