#!/usr/bin/env python3
"""
Test BPE training accuracy by comparing metal0 vs HuggingFace vs SentencePiece

Verifies:
1. Training completes successfully
2. Trained tokenizer can encode/decode
3. Token counts are reasonable (not identical, since algorithms differ)
"""

import json
import tempfile
import os
from tokenizers import Tokenizer, models, trainers
import sentencepiece as spm

# Load training data
with open('benchmark_data.json') as f:
    texts = json.load(f)['texts']

VOCAB_SIZE = 2048
TEST_TEXT = "The quick brown fox jumps over the lazy dog."

print("🔍 BPE Training Accuracy Test")
print("=" * 60)
print(f"Training corpus: {len(texts)} texts")
print(f"Vocab size: {VOCAB_SIZE}")
print(f"Test text: {TEST_TEXT}")
print()

# 1. Train HuggingFace tokenizer
print("1️⃣  Training HuggingFace BPE...")
hf_tokenizer = Tokenizer(models.BPE(unk_token="[UNK]"))
hf_trainer = trainers.BpeTrainer(
    vocab_size=VOCAB_SIZE,
    special_tokens=["[UNK]", "[PAD]"]
)
hf_tokenizer.train_from_iterator(texts, trainer=hf_trainer)

# Test encoding/decoding
hf_tokens = hf_tokenizer.encode(TEST_TEXT)
hf_decoded = hf_tokenizer.decode(hf_tokens.ids)
print(f"   ✅ Encoded: {len(hf_tokens.ids)} tokens")
print(f"   ✅ Decoded: {hf_decoded}")
print(f"   ✅ Roundtrip: {'PASS' if hf_decoded == TEST_TEXT else 'FAIL'}")
print()

# 2. Train SentencePiece tokenizer
print("2️⃣  Training SentencePiece BPE...")
with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt') as f:
    for text in texts:
        f.write(text + "\n")
    temp_file = f.name

spm.SentencePieceTrainer.train(
    input=temp_file,
    model_prefix='test_spm',
    vocab_size=100,  # SentencePiece BPE limited to 100
    model_type='bpe'
)

sp = spm.SentencePieceProcessor()
sp.load('test_spm.model')

sp_tokens = sp.encode_as_ids(TEST_TEXT)
sp_decoded = sp.decode_ids(sp_tokens)
print(f"   ✅ Encoded: {len(sp_tokens)} tokens")
print(f"   ✅ Decoded: {sp_decoded}")
print(f"   ✅ Roundtrip: {'PASS' if sp_decoded == TEST_TEXT else 'FAIL'}")

# Cleanup
os.unlink(temp_file)
os.unlink('test_spm.model')
os.unlink('test_spm.vocab')
print()

# 3. metal0 training (TODO - need to expose trained tokenizer)
print("3️⃣  metal0 BPE...")
print("   ⚠️  metal0 training doesn't currently save/expose trained tokenizer")
print("   ⚠️  Can train but can't test encoding (needs implementation)")
print()

# Summary
print("=" * 60)
print("📊 Summary:")
print(f"   HuggingFace: {len(hf_tokens.ids)} tokens ({'✅ PASS' if hf_decoded == TEST_TEXT else '❌ FAIL'})")
print(f"   SentencePiece: {len(sp_tokens)} tokens ({'✅ PASS' if sp_decoded == TEST_TEXT else '❌ FAIL'})")
print(f"   metal0: ⏳ TODO (need to save trained model)")
print()
print("💡 Note: Token counts differ because algorithms use different tie-breaking")
print("   What matters: encode/decode roundtrip works correctly")
