# Regex Benchmark Guide

## Quick Start

```bash
# Official comparison (recommended)
make benchmark-hyperfine

# Realistic data (1.5MB)
make benchmark-realistic

# Individual languages
make benchmark-zig
make benchmark-rust
make benchmark-python
make benchmark-go
```

## Benchmark Types

### 1. Official Comparison (`make benchmark-hyperfine`)

**Uses:** hyperfine (statistical rigor, 10 runs, 3 warmup)
**Data:** 741 bytes (high iteration counts)
**Output:** Markdown table in `benchmark_results.md`

Example output:
```
PyAOT:  1.303s ± 0.014s
Rust:   4.793s ± 0.873s

PyAOT 3.68x faster! 🏆
```

### 2. Realistic Data (`make benchmark-realistic`)

**Uses:** Direct execution
**Data:** 1.5MB (industry standard, based on rebar/ripgrep)
**Iterations:** Reduced (100-1000 vs 1M) for reasonable runtime

Content:
- 2,000 emails
- 4,500 URLs  
- 98,080 digit sequences
- 96,540 words
- 285 ISO dates

### 3. Individual Benchmarks

All use hyperfine for accurate statistical measurement:
- `make benchmark-zig` - PyAOT only
- `make benchmark-rust` - Rust only
- `make benchmark-python` - Python only
- `make benchmark-go` - Go only

## Data Size Considerations

### Small Data (741 bytes) - Default
**Pros:**
- High iteration counts possible (1M)
- Shows best-case performance
- Common for short text matching

**Cons:**
- Fits in L1 cache (32KB)
- Amplifies prefix scanning benefits
- Not representative of large-scale regex

### Realistic Data (1.5MB)
**Pros:**
- Industry standard size (rebar uses multi-MB)
- Tests memory bandwidth, not cache
- More realistic performance

**Cons:**
- Lower iteration counts (~100-1000)
- Takes longer to run

## How Optimizations Work

Both PyAOT and Rust use **automatic pattern analysis**:

### Rust:
1. Parse regex → HIR (High-level IR)
2. Extract literals automatically
3. Build memchr/Teddy SIMD searchers
4. Run optimized matcher

### PyAOT:
1. Parse regex → AST
2. `optimizer.analyze(ast)` → Detect strategy
3. Enable fast paths (SIMD/prefix/word boundary)
4. Run optimized matcher

**Key difference:** Rust hides it (black box), PyAOT shows it (prints `[AUTO]`)

## Fairness

Both implementations use pattern-specific optimizations:
- ✅ No hardcoding (automatic AST/HIR analysis)
- ✅ 100% Python regex compatible
- ✅ Same data, same iterations
- ✅ Both in release mode

## References

- [rebar](https://github.com/BurntSushi/rebar) - Regex benchmark framework
- [ripgrep](https://github.com/BurntSushi/ripgrep) - Fast grep using Rust regex
- [Regex internals](https://burntsushi.net/regex-internals/) - How Rust regex works
