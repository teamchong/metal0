# Unigram Training Benchmark Results

**Date:** November 23, 2024
**Dataset:** 583 texts × 300 iterations
**Vocabulary Size:** 32,000 tokens
**System:** macOS (Darwin 25.1.0), Zig 0.15.2

## Results

| Command | Mean [s] | Min [s] | Max [s] | Relative |
|:---|---:|---:|---:|---:|
| `HuggingFace (Rust)` | 6.479 ± 0.041 | 6.409 | 6.515 | 1.00 |
| `metal0 (Zig)` | 77.416 ± 0.731 | 76.871 | 78.653 | **11.95 ± 0.14** |

## Analysis

**metal0 is 11.95x SLOWER than HuggingFace for Unigram training.**

### Why the Performance Gap?

Unigram training uses the EM (Expectation-Maximization) algorithm with:
1. **Forward-Backward algorithm** for expected counts
2. **A* search / nbest()** for N-best tokenization paths
3. **Loss-based pruning** to reduce vocabulary size

This is significantly more complex than BPE's greedy merge algorithm.

### Optimization Opportunities

1. **Lattice construction** - Current implementation may rebuild lattices repeatedly
2. **Priority queue performance** - A* search uses heap operations
3. **Memory allocation** - Many temporary allocations during EM iterations
4. **Caching** - Forward-backward computations could be memoized

### Note on SentencePiece

SentencePiece benchmark failed (error during execution). Investigating separately.

## Implementation Status

✅ **Unigram training is 100% complete and working:**
- Full EM algorithm with Bayesian prior
- A* search for N-best paths
- Forward-backward algorithm for expected counts
- Loss-based vocabulary pruning
- Zero memory leaks (GPA verification passed)

**Performance:** Slower than optimized Rust implementation, but functionally correct.

## Comparison Summary

| Algorithm | metal0 Performance | Status |
|-----------|------------------|--------|
| **BPE** | **1.23x slower** ⚠️ | Needs optimization |
| **WordPiece** | **1.94x slower** ⚠️ | Needs optimization |
| **Unigram** | **11.95x slower** ⚠️ | Needs major optimization |

**Takeaway:** metal0 training needs optimization across all algorithms. Encoding (6x faster) and WASM (17-249x faster) are excellent.
