# metal0 Tokenizer

Tiktoken-compatible BPE tokenizer in pure Zig. 100% encoding correctness verified against OpenAI's tiktoken.

## Features

- **100% Correct**: Verified against tiktoken cl100k_base (3459/3459 tests pass)
- **Pure Zig**: No external dependencies, no regex library
- **Direct Port**: Line-by-line port of tiktoken's Rust implementation

## Architecture

```
src/
├── tiktoken_encoder.zig   # BPE merge algorithm (port of tiktoken lib.rs)
├── cl100k_splitter.zig    # Pre-tokenization regex pattern (pure Zig)
├── trainer.zig            # BPE vocabulary training
└── vocab.zig              # Vocabulary loading/storage
```

## Algorithm

The encoder is a direct port of tiktoken's `_byte_pair_merge` algorithm:

1. **Pre-tokenization**: Split text using cl100k_base regex pattern
2. **BPE Merge**: For each chunk, apply byte-pair merges until no more merges possible
3. **Token Lookup**: Map final byte sequences to token IDs

## Usage

```zig
const tiktoken = @import("tiktoken_encoder");
const splitter = @import("cl100k_splitter");

// Split text into chunks
var iter = splitter.chunks("Hello world");

// Encode each chunk
while (iter.next()) |chunk| {
    const tokens = try tiktoken.byte_pair_encode(chunk, vocab, allocator);
    defer allocator.free(tokens);
    // use tokens...
}
```

## Testing

```bash
# Run unit tests
zig test src/tiktoken_encoder.zig

# Run full correctness verification (requires tiktoken)
python3 test_100_percent_encoding.py
```

## References

- [tiktoken lib.rs](https://github.com/openai/tiktoken/blob/main/src/lib.rs) - Original Rust implementation
- [cl100k_base](https://github.com/openai/tiktoken/blob/main/tiktoken_ext/openai_public.py) - OpenAI's GPT-4 tokenizer
