# Tokenizer Benchmark Results

**Platform:** macOS ARM64 (Apple Silicon)
**Date:** 2024-11-19
**Zig:** 0.15.2
**Build:** --release=fast

---

## Results

| Benchmark | bpe/rust-gems (Rust) | HuggingFace | Zig PyAOT |
|-----------|---------------------|-------------|-----------|
| **Training** (15K texts, 2048 vocab) | TBD | TBD | **313ms** |
| **Encoding** (305 bytes/iter) | TBD | TBD | **1095μs** |
| **Throughput** | TBD | ~50 MB/s | **0.28 MB/s** |
| **Memory** | TBD | TBD | **2 KB** |

**Notes:**
- bpe/rust-gems: Fastest Rust implementation (10x faster than HuggingFace)
- HuggingFace: Industry standard (50 MB/s throughput)
- Zig PyAOT: Current status with Phase 1+2 optimizations

**Next:** Test bpe/rust-gems and HuggingFace on same hardware
