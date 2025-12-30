#!/usr/bin/env python3
"""Test if lance file embeddings match CLIP model."""

import open_clip
import torch
import numpy as np

# Load CLIP model
print("Loading CLIP model...")
model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
model.eval()
tokenizer = open_clip.get_tokenizer('ViT-B-32')

# Encode test texts
test_texts = [
    "a photo of a cat",
    "a photo of a dog",
    "food on a plate",
    "a sunset over the ocean"
]

print("\nCLIP text embeddings:")
for text in test_texts:
    tokens = tokenizer([text])
    with torch.no_grad():
        emb = model.encode_text(tokens)
        emb = emb / emb.norm(dim=-1, keepdim=True)
        emb = emb[0].numpy()
    print(f'  "{text}": [{emb[0]:.4f}, {emb[1]:.4f}, {emb[2]:.4f}, {emb[3]:.4f}, ...]')

# Now let's check what model the lance file embeddings might be from
# by computing similarity with known CLIP embeddings
print("\nExpected similarity between 'a photo of a cat' and 'a photo of a dog':")
tokens1 = tokenizer(["a photo of a cat"])
tokens2 = tokenizer(["a photo of a dog"])
with torch.no_grad():
    emb1 = model.encode_text(tokens1)
    emb1 = emb1 / emb1.norm(dim=-1, keepdim=True)
    emb2 = model.encode_text(tokens2)
    emb2 = emb2 / emb2.norm(dim=-1, keepdim=True)
    sim = (emb1 @ emb2.T).item()
print(f"  Cosine similarity: {sim:.4f}")

print("\nIf your lance file has CLIP text embeddings from the same model,")
print("searching 'a photo of a cat' should return texts about cats with high similarity (>0.7).")
print("\nIf similarity is low (~0.15), the embeddings are likely from a different model.")
