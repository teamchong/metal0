"""
metal0 WASM tokenizer (Python → WASM)

Exports tokenizer functions for browser/WASM usage.
Compile with: metal0 build --target wasm32 wasm_tokenizer_metal0.py

Exported functions:
    - init(vocab_path: str) -> bool
    - encode(text: str) -> list[int]
    - decode(tokens: list[int]) -> str
"""

from metal0 import tokenizer

# Global state
_initialized = False

def init(vocab_path: str) -> bool:
    """Initialize tokenizer with vocabulary file."""
    global _initialized
    tokenizer.init(vocab_path)
    _initialized = True
    return True

def encode(text: str) -> list:
    """Encode text to token IDs."""
    if not _initialized:
        return []
    return tokenizer.encode(text)

def decode(tokens: list) -> str:
    """Decode token IDs to text."""
    if not _initialized:
        return ""
    return tokenizer.decode(tokens)

# Export for WASM
__exports__ = ["init", "encode", "decode"]
