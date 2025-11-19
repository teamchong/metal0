# Tokenizer Benchmark Results

**Platform:** macOS ARM64 (Apple Silicon)
**Date:** 2024-11-19
**Zig:** 0.15.2
**Build:** --release=fast

---

## Results

| Benchmark | Rust Baseline | Zig PyAOT | Relative |
|-----------|---------------|-----------|----------|
| **Training** (15K texts, 2048 vocab) | **22ms** | **313ms** | **14x slower** ❌ |
| **Encoding** (305 bytes/iter) | **159μs** | **1095μs** | **6.9x slower** ❌ |
| **Throughput** | **1.92 MB/s** | **0.28 MB/s** | **6.9x slower** ❌ |
| **Memory** | ~11 KB | **2 KB** | **5.5x better** ✅ |

**Same benchmark data:** 15,000 texts, vocab 2048, 305-byte encoding test

**Status:** HashMap lookup added but encoding still slow (scanning tokens wrong way)

**Next:** Fix encoding algorithm properly
