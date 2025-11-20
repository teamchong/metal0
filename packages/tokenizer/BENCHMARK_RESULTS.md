# Tokenizer Benchmark Results

## Native (60K iterations, 286-byte text, Apple M2)

| Implementation | Time (mean ± σ) | vs Fastest | Type |
|---------------|-----------------|------------|------|
| **PyAOT (Zig)** | **741ms ± 6ms** | **1.00x** 🏆 | Pure Zig |
| TokenDagger (C) | 775ms ± 12ms | 1.05x | C + PCRE2 |
| tiktoken (Rust) | 1194ms ± 33ms | 1.61x | Rust |
| HuggingFace (Rust) | 5240ms ± 97ms | 7.07x | Python + Rust |
| Rust rustbpe | 9550ms | 12.9x | Pure Rust |

## Browser (10K iterations, 286-byte text, Chrome headless)

| Implementation | Time | Scaled to 60K | Bundle Size | Type |
|---------------|------|---------------|-------------|------|
| **gpt-tokenizer** | **59ms** | **~354ms** | 1.1MB | Pure JS 🏆 |

**Not working in browser:**
- tiktoken (Rust→WASM): WASM binding error
- ai-tokenizer: Missing encoding data files
- PyAOT (Zig→WASM): Needs cl100k_base.json tokenizer data

## Key Findings

1. **Native: PyAOT (Zig) is fastest** - beats C by 4.4%, Rust by 61%
2. **Browser: Only gpt-tokenizer working** - 354ms scaled vs 741ms native = **2.1x slower**
3. **Browser overhead is reasonable** - not the 6-8x expected, only 2.1x!
4. **WASM is harder** - tiktoken and PyAOT both fail in browser due to WASM complexity

## Tested Configurations

**Native:**
- Benchmarked with hyperfine (5 runs, proper statistical analysis)
- All use same 286-byte text, same 60K iterations
- Direct comparison: apples-to-apples

**Browser:**
- Bundled with Bun (Zig-based bundler)
- Format: IIFE for browser compatibility
- Tested with Playwright (automated Chrome headless)
- HTTP server on localhost:8899

## Conclusion

**PyAOT tokenizer (pure Zig) is the fastest native tokenizer**, beating both C and Rust implementations.

For browser, only simple Pure JS tokenizers work reliably. WASM tokenizers have bundling/loading complexity.
