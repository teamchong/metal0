## Unigram Training Performance (VOCAB_SIZE=751)

| Command | Mean [ms] | Relative |
|:---|---:|---:|
| **PyAOT (Zig ReleaseFast)** | **108** | **2.4x faster** 🚀 |
| HuggingFace (Rust release) | 263 | 1.00 |

**Result: PyAOT beats HuggingFace by 2.4x!** ✅

---

## BPE Training Performance (Full Benchmark)

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `PyAOT (Zig)` | 1.095 ± 0.009 | 1.084 | 1.106 | 1.00 |
| `HuggingFace (Rust)` | 26.690 ± 0.145 | 26.536 | 26.848 | 24.37 ± 0.23 |
| `SentencePiece (C++)` | 8.514 ± 0.112 | 8.391 | 8.694 | 7.78 ± 0.12 |
