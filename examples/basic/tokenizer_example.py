"""
Tokenizer examples using metal0's native Zig tokenizer.

Usage:
    metal0 tokenizer_example.py

The `from metal0 import tokenizer` uses the native Zig BPE tokenizer,
which is 248x faster than tiktoken WASM.
"""

from metal0 import tokenizer


def basic_encode():
    """Example 1: Basic BPE encoding"""
    text = "Hello world!"

    tokens = tokenizer.encode(text)
    print("Text:", text)
    print("Tokens:", tokens)

    # Decode back
    decoded = tokenizer.decode(tokens)
    print("Decoded:", decoded)


def count_tokens():
    """Example 2: Count tokens without allocation"""
    text = "This is a longer text that we want to count tokens for."

    count = tokenizer.count_tokens(text)
    print("Text:", text)
    print("Token count:", count)


def batch_encode():
    """Example 3: Batch encoding multiple texts"""
    texts = [
        "Hello world!",
        "How are you?",
        "I'm doing great, thanks!",
    ]

    for text in texts:
        tokens = tokenizer.encode(text)
        print(text, "->", len(tokens), "tokens")


if __name__ == "__main__":
    print("=== Example 1: Basic Encode ===")
    basic_encode()

    print("\n=== Example 2: Count Tokens ===")
    count_tokens()

    print("\n=== Example 3: Batch Encode ===")
    batch_encode()
