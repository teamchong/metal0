#!/usr/bin/env python3
"""
Create a demo translations dataset for testing OPFS JOINs.

This creates a Lance file with simulated translations (prefixed captions)
and real multilingual embeddings for cross-lingual vector search.

For production, use translate_captions.py with a real translation service.

Usage:
    python create_demo_translations.py --input images.lance --output translations.lance --limit 10000
"""

import argparse
import lance
import pyarrow as pa
import numpy as np
from sentence_transformers import SentenceTransformer
from pathlib import Path
from tqdm import tqdm


def get_storage_options(dataset_path):
    """Get R2 storage options for S3 paths."""
    if not dataset_path.startswith('s3://'):
        return None

    import subprocess
    try:
        access_key = subprocess.run(
            ["aws", "configure", "get", "aws_access_key_id", "--profile", "r2"],
            capture_output=True, text=True
        ).stdout.strip()
        secret_key = subprocess.run(
            ["aws", "configure", "get", "aws_secret_access_key", "--profile", "r2"],
            capture_output=True, text=True
        ).stdout.strip()

        if access_key and secret_key:
            return {
                "endpoint": "https://36498dc359676cbbcf8c3616e6c07e94.r2.cloudflarestorage.com",
                "region": "auto",
                "aws_access_key_id": access_key,
                "aws_secret_access_key": secret_key,
            }
    except Exception:
        pass
    return None


def create_demo_translations(dataset_path, output_path, target_langs=['zh', 'es', 'ja'],
                              limit=None, embed_batch_size=512):
    """
    Create a demo translations dataset with simulated translations but real embeddings.

    The "translations" are just prefixed versions of the English text for demo purposes.
    Real multilingual embeddings are generated using paraphrase-multilingual-MiniLM-L12-v2.
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading dataset from: {dataset_path}")

    # Handle HTTP URLs by converting to S3 path
    if dataset_path.startswith('https://data.metal0.dev/'):
        s3_path = dataset_path.replace('https://data.metal0.dev/', 's3://metal0-data/')
        print(f"Converting to S3: {s3_path}")
        storage_options = get_storage_options(s3_path)
        if storage_options:
            ds = lance.dataset(s3_path, storage_options=storage_options)
        else:
            raise ValueError("Failed to get R2 credentials. Configure 'r2' aws profile.")
    elif dataset_path.startswith('s3://'):
        storage_options = get_storage_options(dataset_path)
        ds = lance.dataset(dataset_path, storage_options=storage_options)
    else:
        ds = lance.dataset(dataset_path)

    # Read captions
    print("Reading captions...")
    table = ds.to_table(columns=['text'])

    if limit:
        print(f"Limiting to {limit} captions")
        table = table.slice(0, limit)

    captions = [row['text'] for row in table.to_pylist()]
    total = len(captions)
    print(f"Loaded {total:,} captions")

    # Initialize data dict with English text
    data = {
        'text_en': captions,
    }

    # Create simulated translations (just prefixed for demo)
    prefixes = {
        'zh': '[ZH] ',
        'es': '[ES] ',
        'ja': '[JA] ',
        'fr': '[FR] ',
        'de': '[DE] ',
    }

    for lang_code in target_langs:
        prefix = prefixes.get(lang_code, f'[{lang_code.upper()}] ')
        print(f"Creating simulated {lang_code.upper()} translations...")
        data[f'text_{lang_code}'] = [prefix + (text or '') for text in captions]

    # Generate embeddings using multilingual model
    print("\n" + "=" * 60)
    print("Generating multilingual embeddings...")
    print("=" * 60)

    embed_model = SentenceTransformer("sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
    print(f"Loaded embedding model: paraphrase-multilingual-MiniLM-L12-v2")
    print(f"Embedding dimension: {embed_model.get_sentence_embedding_dimension()}")

    # Generate embeddings for all text columns
    text_columns = ['en'] + target_langs
    for lang_code in text_columns:
        col_name = f'text_{lang_code}'
        if col_name not in data:
            continue

        print(f"\nGenerating {lang_code.upper()} embeddings...")
        texts = data[col_name]
        embeddings = []
        for i in tqdm(range(0, total, embed_batch_size)):
            batch = texts[i:i + embed_batch_size]
            emb = embed_model.encode(batch, show_progress_bar=False, normalize_embeddings=True)
            embeddings.extend(emb.tolist())
        data[f'embedding_{lang_code}'] = embeddings

    # Convert to PyArrow table
    print("\nCreating PyArrow table...")
    embedding_dim = embed_model.get_sentence_embedding_dimension()

    # Build schema
    fields = []
    for lang_code in ['en'] + target_langs:
        text_col = f'text_{lang_code}'
        if text_col in data:
            fields.append(pa.field(text_col, pa.string()))
    for lang_code in ['en'] + target_langs:
        emb_col = f'embedding_{lang_code}'
        if emb_col in data:
            fields.append(pa.field(emb_col, pa.list_(pa.float32(), embedding_dim)))

    schema = pa.schema(fields)

    # Convert to PyArrow arrays
    arrays = []
    for field in fields:
        col = field.name
        if col.startswith('text_'):
            arrays.append(pa.array(data[col], type=pa.string()))
        elif col.startswith('embedding_'):
            flat = np.array(data[col], dtype=np.float32).flatten()
            arrays.append(pa.FixedSizeListArray.from_arrays(pa.array(flat), embedding_dim))

    table = pa.Table.from_arrays(arrays, schema=schema)

    # Write to Lance
    print(f"\nWriting to {output_path}...")
    lance.write_dataset(table, str(output_path))

    print("\n" + "=" * 60)
    print("Demo translations dataset created!")
    print("=" * 60)
    print(f"Output: {output_path}")
    print(f"Rows: {total:,}")
    print(f"Columns: {', '.join([f.name for f in fields])}")
    print(f"\nNote: Translations are simulated (prefixed English).")
    print("For real translations, use translate_captions.py")


def main():
    parser = argparse.ArgumentParser(description='Create demo translations dataset')
    parser.add_argument('--input', required=True, help='Path to input Lance dataset')
    parser.add_argument('--output', default='translations.lance', help='Output path')
    parser.add_argument('--languages', default='zh,es,ja', help='Comma-separated language codes')
    parser.add_argument('--limit', type=int, default=10000, help='Limit rows (default: 10000)')
    parser.add_argument('--embed-batch-size', type=int, default=512, help='Embedding batch size')

    args = parser.parse_args()
    target_langs = [lang.strip() for lang in args.languages.split(',')]

    print("=" * 60)
    print("Demo Translations Dataset (Simulated)")
    print("=" * 60)
    print(f"Input: {args.input}")
    print(f"Output: {args.output}")
    print(f"Languages: en, {', '.join(target_langs)}")
    print(f"Limit: {args.limit}")
    print("=" * 60)

    create_demo_translations(
        dataset_path=args.input,
        output_path=args.output,
        target_langs=target_langs,
        limit=args.limit,
        embed_batch_size=args.embed_batch_size
    )


if __name__ == '__main__':
    main()
