# Tokenizer Benchmark Results

**Platform:** macOS ARM64 (Apple Silicon)
**Date:** 2024-11-19
**Zig:** 0.15.2
**Build:** --release=fast

---

## Hyperfine Results (10 runs, same workload)

| Implementation | Mean | Std Dev | Relative |
|----------------|------|---------|----------|
| **Rust baseline** | **31.6ms** | ±0.4ms | **1.00x** ✅ |
| **Zig PyAOT** | **607.1ms** | ±17.8ms | **19.2x slower** ❌ |

**Workload:** 500 texts training (vocab 300) + 1000 encoding iterations

**Why slow:**
- Training: PriorityQueue added, but Rust uses parallel training (rayon)
- Encoding: Scanning all tokens repeatedly instead of applying merges in order

**Next:** Fix encoding algorithm (apply merges sequentially, not scan repeatedly)
