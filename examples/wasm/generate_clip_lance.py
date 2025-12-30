#!/usr/bin/env python3
"""
Generate a lance file with CLIP ViT-B-32 text embeddings.
This creates a compatible dataset for the CLIP text search feature.
"""

import lance
from lance import write_dataset
import pyarrow as pa
import open_clip
import torch
import numpy as np
from tqdm import tqdm

# Sample data - image URLs and captions
# You can replace this with data from your actual dataset
SAMPLE_DATA = [
    ("https://example.com/cat1.jpg", "a photo of a cat sitting on a couch"),
    ("https://example.com/cat2.jpg", "a cute orange cat sleeping"),
    ("https://example.com/dog1.jpg", "a photo of a dog playing fetch"),
    ("https://example.com/dog2.jpg", "a golden retriever in the park"),
    ("https://example.com/sunset1.jpg", "a beautiful sunset over the ocean"),
    ("https://example.com/sunset2.jpg", "orange and purple sunset sky"),
    ("https://example.com/food1.jpg", "food on a plate, delicious pasta"),
    ("https://example.com/food2.jpg", "a bowl of fresh salad"),
    ("https://example.com/city1.jpg", "a city skyline at night"),
    ("https://example.com/city2.jpg", "new york city buildings"),
    ("https://example.com/nature1.jpg", "a mountain landscape with snow"),
    ("https://example.com/nature2.jpg", "a forest with tall trees"),
    ("https://example.com/beach1.jpg", "people at the beach on a sunny day"),
    ("https://example.com/car1.jpg", "a red sports car on the road"),
    ("https://example.com/flower1.jpg", "colorful flowers in a garden"),
]

def main():
    print("Loading CLIP model (ViT-B-32)...")
    model, _, preprocess = open_clip.create_model_and_transforms('ViT-B-32', pretrained='laion2b_s34b_b79k')
    model.eval()
    tokenizer = open_clip.get_tokenizer('ViT-B-32')

    print(f"Generating embeddings for {len(SAMPLE_DATA)} samples...")

    urls = []
    texts = []
    embeddings = []

    for url, text in tqdm(SAMPLE_DATA):
        urls.append(url)
        texts.append(text)

        # Encode text with CLIP
        tokens = tokenizer([text])
        with torch.no_grad():
            emb = model.encode_text(tokens)
            emb = emb / emb.norm(dim=-1, keepdim=True)  # L2 normalize
            emb = emb[0].numpy().astype(np.float32)
        embeddings.append(emb)

    # Create PyArrow table with FixedSizeList for embeddings
    print("Creating Lance file...")

    # Use FixedSizeList for vector embeddings (512-dim)
    embedding_type = pa.list_(pa.float32(), 512)
    embedding_array = pa.array([emb.tolist() for emb in embeddings], type=embedding_type)

    table = pa.table({
        'url': pa.array(urls, type=pa.utf8()),
        'text': pa.array(texts, type=pa.utf8()),
        'embedding': embedding_array,
    })

    # Write to Lance format
    output_path = "clip_sample.lance"
    write_dataset(table, output_path, mode="overwrite")

    print(f"Saved to {output_path}")
    print(f"  - {len(urls)} rows")
    print(f"  - Embedding dimension: {embeddings[0].shape[0]}")

    # Verify by reading back
    ds = lance.dataset(output_path)
    print(f"\nVerification:")
    print(f"  - Rows: {ds.count_rows()}")
    print(f"  - Schema: {ds.schema}")

    # Test search
    print("\nTest search for 'cat'...")
    query_tokens = tokenizer(["a photo of a cat"])
    with torch.no_grad():
        query_emb = model.encode_text(query_tokens)
        query_emb = query_emb / query_emb.norm(dim=-1, keepdim=True)
        query_emb = query_emb[0].numpy()

    # Compute similarities
    for i, (url, text) in enumerate(SAMPLE_DATA):
        sim = np.dot(query_emb, embeddings[i])
        if sim > 0.7:
            print(f"  {sim:.4f}: {text}")

if __name__ == "__main__":
    main()
