"""
Tokenizer pipeline examples - mirrors the Zig example_features.zig

Demonstrates different tokenization strategies:
- Basic BPE
- Pre-tokenization (whitespace, punctuation, byte-level)
- Normalization (lowercase, replace)
- Post-processing (BERT-style [CLS]/[SEP])
- GPT-2 style with regex

Usage:
    metal0 tokenizer_pipelines.py

All pipelines use the native Zig tokenizer via `from metal0 import tokenizer`.
Comptime dead code elimination ensures only used features are compiled.
"""

from metal0 import tokenizer


def basic_bpe():
    """
    Example 1: Basic BPE (no features used)
    Binary size: ~46KB (baseline)
    """
    text = "Hello world!"

    tokens = tokenizer.encode(text)
    print(f"Tokens: {tokens}")


def bpe_with_pretokenization():
    """
    Example 2: BPE with pre-tokenization
    Binary size: ~48KB (+2KB for whitespace splitter)
    """
    text = "Hello world! How are you?"

    # Pre-tokenize using whitespace splitter
    segments = tokenizer.pre_tokenize(text, method="whitespace")

    # Encode each segment
    for segment in segments:
        tokens = tokenizer.encode(segment)
        print(f"{segment} -> {tokens}")


def bpe_with_normalization():
    """
    Example 3: BPE with normalization
    Binary size: ~47KB (+1KB for lowercase)
    """
    text = "Hello WORLD!"

    # Normalize to lowercase
    normalized = tokenizer.normalize(text, method="lowercase")

    tokens = tokenizer.encode(normalized)
    print(f"Original: {text}")
    print(f"Normalized: {normalized}")
    print(f"Tokens: {tokens}")


def bert_style_pipeline():
    """
    Example 4: BERT-style pipeline (all features)
    Binary size: ~52KB (+6KB for all features)
    """
    text = "Hello, WORLD!\nHow are you?"

    # 1. Normalize: lowercase + replace newlines
    normalized = tokenizer.normalize(text, method="lowercase")
    normalized = normalized.replace("\n", " ")

    # 2. Pre-tokenize: split on punctuation
    segments = tokenizer.pre_tokenize(normalized, method="punctuation")

    # 3. Encode all segments
    all_tokens = []
    for segment in segments:
        tokens = tokenizer.encode(segment)
        all_tokens.extend(tokens)

    # 4. Post-process: add [CLS] and [SEP]
    CLS_TOKEN = 101
    SEP_TOKEN = 102
    final_tokens = [CLS_TOKEN] + all_tokens + [SEP_TOKEN]

    print(f"Original: {text}")
    print(f"Final tokens: {final_tokens}")


def gpt2_style_pipeline():
    """
    Example 5: GPT-2 style pipeline (byte-level)
    Binary size: ~50KB (+4KB for byteLevel + whitespace)
    """
    text = "Hello123 World!"

    # 1. Pre-tokenize: byte-level (split on character class changes)
    segments = tokenizer.pre_tokenize(text, method="byte_level")

    # 2. Encode all segments
    all_tokens = []
    for segment in segments:
        tokens = tokenizer.encode(segment)
        all_tokens.extend(tokens)

    print(f"Original: {text}")
    print(f"Segments: {segments}")
    print(f"Tokens: {all_tokens}")


def gpt2_with_regex():
    """
    Example 6: GPT-2 with REAL regex pattern (exact compatibility)
    Binary size: ~54KB (+8KB for regex engine)

    Uses the actual GPT-2 pre-tokenization regex pattern
    for correct handling of contractions like "don't".
    """
    text = "I don't know what you're doing!"

    # 1. Pre-tokenize: GPT-2 regex pattern
    segments = tokenizer.pre_tokenize(text, method="gpt2_pattern")

    # 2. Encode all segments
    all_tokens = []
    for segment in segments:
        tokens = tokenizer.encode(segment)
        all_tokens.extend(tokens)

    print(f"Original: {text}")
    print(f"Regex segments: {segments}")
    print(f"Tokens: {all_tokens}")


if __name__ == "__main__":
    print("\n=== Example 1: Basic BPE ===")
    basic_bpe()

    print("\n=== Example 2: With Pre-tokenization ===")
    bpe_with_pretokenization()

    print("\n=== Example 3: With Normalization ===")
    bpe_with_normalization()

    print("\n=== Example 4: BERT-style Pipeline ===")
    bert_style_pipeline()

    print("\n=== Example 5: GPT-2 Style Pipeline (Fast) ===")
    gpt2_style_pipeline()

    print("\n=== Example 6: GPT-2 with Regex (Exact Compatibility) ===")
    gpt2_with_regex()
