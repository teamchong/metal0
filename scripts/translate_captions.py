#!/usr/bin/env python3
"""
Translate LAION-1M captions to multiple languages and generate embeddings.

Uses CTranslate2 for fast inference (3-10x faster than HuggingFace Transformers).

Usage:
    python translate_captions.py --input images.lance --output translations.lance

Output schema:
    | text_en | text_zh | text_es | text_ja | embedding_en (384d) | embedding_zh (384d) | ...

Requirements:
    pip install lance pyarrow sentence-transformers numpy ctranslate2 transformers
"""

import argparse
import lance
import pyarrow as pa
import numpy as np
from sentence_transformers import SentenceTransformer
from pathlib import Path
from tqdm import tqdm
import ctranslate2
import transformers
import gc


# NLLB language codes (flores-200 codes)
NLLB_LANGS = {
    'en': 'eng_Latn',
    'zh': 'zho_Hans',
    'es': 'spa_Latn',
    'ja': 'jpn_Jpan',
    'fr': 'fra_Latn',
    'de': 'deu_Latn',
    'ko': 'kor_Hang',
    'ru': 'rus_Cyrl',
    'ar': 'arb_Arab',
    'pt': 'por_Latn',
}


class CT2Translator:
    """Fast translation using CTranslate2 with NLLB model."""

    def __init__(self, model_path=None):
        """
        Initialize CTranslate2 translator with NLLB model.

        Args:
            model_path: Path to converted CT2 model. If None, will download and convert.
        """
        if model_path is None:
            model_path = self._get_or_convert_model()

        print(f"Loading CTranslate2 model from: {model_path}")
        self.translator = ctranslate2.Translator(model_path, device="auto", compute_type="auto")
        self.tokenizer = transformers.AutoTokenizer.from_pretrained(
            "facebook/nllb-200-distilled-600M",
            src_lang="eng_Latn"
        )
        print(f"Using device: {self.translator.device}")

    def _get_or_convert_model(self):
        """Get or convert the NLLB model to CTranslate2 format."""
        import os
        ct2_model_path = os.path.expanduser("~/.cache/ct2_models/nllb-200-distilled-600M")

        if os.path.exists(ct2_model_path):
            return ct2_model_path

        print("Converting NLLB model to CTranslate2 format (one-time operation)...")
        os.makedirs(os.path.dirname(ct2_model_path), exist_ok=True)

        # Convert using ct2-transformers-converter
        import subprocess
        result = subprocess.run([
            "ct2-transformers-converter",
            "--model", "facebook/nllb-200-distilled-600M",
            "--output_dir", ct2_model_path,
            "--quantization", "int8",  # Use int8 for faster inference
            "--force"
        ], capture_output=True, text=True)

        if result.returncode != 0:
            print(f"Conversion error: {result.stderr}")
            raise RuntimeError("Failed to convert model")

        print(f"Model converted and saved to: {ct2_model_path}")
        return ct2_model_path

    def translate_batch(self, texts, src_lang='eng_Latn', tgt_lang='zho_Hans', batch_size=64):
        """
        Translate texts using CTranslate2 (much faster than HuggingFace).

        Args:
            texts: List of strings to translate
            src_lang: Source language (NLLB code)
            tgt_lang: Target language (NLLB code)
            batch_size: Batch size for inference
        """
        self.tokenizer.src_lang = src_lang
        results = []

        for i in tqdm(range(0, len(texts), batch_size), desc=f"Translating to {tgt_lang}"):
            batch = texts[i:i + batch_size]

            # Prepare batch
            valid_indices = []
            valid_texts = []
            for j, text in enumerate(batch):
                if text and isinstance(text, str) and len(text.strip()) > 0:
                    # Truncate long texts
                    if len(text) > 400:
                        text = text[:400]
                    valid_texts.append(text)
                    valid_indices.append(j)

            batch_results = [""] * len(batch)

            if valid_texts:
                try:
                    # Tokenize
                    inputs = self.tokenizer(valid_texts, return_tensors="pt", padding=True, truncation=True, max_length=256)
                    input_tokens = [self.tokenizer.convert_ids_to_tokens(ids) for ids in inputs["input_ids"]]

                    # Translate with CTranslate2
                    target_prefix = [[tgt_lang]] * len(input_tokens)
                    translations = self.translator.translate_batch(
                        input_tokens,
                        target_prefix=target_prefix,
                        max_batch_size=batch_size,
                        beam_size=1,  # Greedy for speed
                        max_decoding_length=256,
                    )

                    # Decode
                    for idx, trans in zip(valid_indices, translations):
                        tokens = trans.hypotheses[0][1:]  # Skip language token
                        text = self.tokenizer.decode(self.tokenizer.convert_tokens_to_ids(tokens), skip_special_tokens=True)
                        batch_results[idx] = text

                except Exception as e:
                    print(f"Batch error: {e}")
                    for idx in valid_indices:
                        batch_results[idx] = batch[idx]

            results.extend(batch_results)

        return results

    def cleanup(self):
        """Free memory."""
        del self.translator
        del self.tokenizer
        gc.collect()


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


def create_translations_dataset(dataset_path, output_path, target_langs=['zh', 'es', 'ja'],
                                 limit=None, embed_batch_size=256, translate_batch_size=64):
    """
    Create translations.lance with all languages as columns + embeddings.
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading dataset from: {dataset_path}")

    # Handle HTTP URLs
    if dataset_path.startswith('https://data.metal0.dev/'):
        s3_path = dataset_path.replace('https://data.metal0.dev/', 's3://metal0-data/')
        print(f"Converting to S3: {s3_path}")
        storage_options = get_storage_options(s3_path)
        if storage_options:
            ds = lance.dataset(s3_path, storage_options=storage_options)
        else:
            raise ValueError("Failed to get R2 credentials")
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

    data = {'text_en': captions}

    # Initialize translator
    translator = CT2Translator()

    # Translate to each language
    for lang_code in target_langs:
        if lang_code not in NLLB_LANGS:
            print(f"Warning: Unsupported language '{lang_code}'")
            continue

        print(f"\n{'='*60}")
        print(f"Translating to {lang_code.upper()}...")
        print(f"{'='*60}")

        translated = translator.translate_batch(
            captions,
            src_lang=NLLB_LANGS['en'],
            tgt_lang=NLLB_LANGS[lang_code],
            batch_size=translate_batch_size
        )
        data[f'text_{lang_code}'] = translated

    translator.cleanup()

    # Generate embeddings
    print("\n" + "=" * 60)
    print("Generating embeddings...")
    print("=" * 60)

    embed_model = SentenceTransformer("sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
    print(f"Model: paraphrase-multilingual-MiniLM-L12-v2 ({embed_model.get_sentence_embedding_dimension()}d)")

    for lang_code in ['en'] + target_langs:
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

    # Build PyArrow table
    print("\nCreating PyArrow table...")
    embedding_dim = embed_model.get_sentence_embedding_dimension()

    fields = []
    for lang_code in ['en'] + target_langs:
        if f'text_{lang_code}' in data:
            fields.append(pa.field(f'text_{lang_code}', pa.string()))
    for lang_code in ['en'] + target_langs:
        if f'embedding_{lang_code}' in data:
            fields.append(pa.field(f'embedding_{lang_code}', pa.list_(pa.float32(), embedding_dim)))

    schema = pa.schema(fields)

    arrays = []
    for field in fields:
        col = field.name
        if col.startswith('text_'):
            arrays.append(pa.array(data[col], type=pa.string()))
        elif col.startswith('embedding_'):
            flat = np.array(data[col], dtype=np.float32).flatten()
            arrays.append(pa.FixedSizeListArray.from_arrays(pa.array(flat), embedding_dim))

    table = pa.Table.from_arrays(arrays, schema=schema)

    print(f"\nWriting to {output_path}...")
    lance.write_dataset(table, str(output_path))

    print("\n" + "=" * 60)
    print("Done!")
    print("=" * 60)
    print(f"Output: {output_path}")
    print(f"Rows: {total:,}")
    print(f"Schema: {', '.join([f.name for f in fields])}")


def main():
    parser = argparse.ArgumentParser(description='Translate captions with CTranslate2')
    parser.add_argument('--input', required=True, help='Input Lance dataset')
    parser.add_argument('--output', default='translations.lance', help='Output path')
    parser.add_argument('--languages', default='zh,es,ja', help='Target languages')
    parser.add_argument('--limit', type=int, default=None, help='Limit rows')
    parser.add_argument('--translate-batch-size', type=int, default=64, help='Translation batch size')
    parser.add_argument('--embed-batch-size', type=int, default=256, help='Embedding batch size')

    args = parser.parse_args()
    target_langs = [l.strip() for l in args.languages.split(',')]

    print("=" * 60)
    print("CTranslate2 Translation Pipeline")
    print("=" * 60)
    print(f"Input: {args.input}")
    print(f"Output: {args.output}")
    print(f"Languages: en -> {', '.join(target_langs)}")
    print(f"Limit: {args.limit or 'All'}")
    print("=" * 60)

    create_translations_dataset(
        dataset_path=args.input,
        output_path=args.output,
        target_langs=target_langs,
        limit=args.limit,
        translate_batch_size=args.translate_batch_size,
        embed_batch_size=args.embed_batch_size
    )


if __name__ == '__main__':
    main()
