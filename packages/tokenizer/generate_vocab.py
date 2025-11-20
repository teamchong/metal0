#!/usr/bin/env python3
"""
Generate proper cl100k_base vocab with all BPE tokens
"""
import tiktoken
import json
import base64

enc = tiktoken.get_encoding('cl100k_base')

# Get full BPE ranks (includes all merged tokens!)
bpe_ranks = enc._mergeable_ranks

# Convert to base64-encoded vocab format
vocab = {}
for token_bytes, rank in bpe_ranks.items():
    token_b64 = base64.b64encode(token_bytes).decode('ascii')
    vocab[token_b64] = rank

print(f"Vocab size: {len(vocab)}")
print(f"First few tokens: {list(vocab.items())[:5]}")
print(f"Sample multi-byte token: {list(vocab.items())[256:261]}")

# Write to file
output = {'vocab': vocab}
with open('dist/cl100k_base_full.json', 'w') as f:
    json.dump(output, f, separators=(',', ':'))

print(f"\n✅ Written to dist/cl100k_base_full.json")
print(f"   This includes all {len(vocab)} BPE tokens (not just 256 bytes)")
