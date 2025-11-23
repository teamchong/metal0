# Multi-Size Benchmark Analysis

**Industry Standard:** Rust regex uses 1KB/32KB/500KB (from rust-lang/regex)

## Why Multiple Sizes?

From RegexBuddy documentation:
> "Test at least three string lengths to verify linear vs quadratic vs exponential growth"

From Rust regex benchmarks:
- 32 bytes: Constant overhead testing
- 1 KB: Cache-friendly (fits in L1)
- 32 KB: L1 cache limit
- 100 KB: Pathological cases
- 0.5 MB: Realistic files
- 150 MB: Entire codebases

## Our Benchmark Results

### Email Pattern (@ prefix optimization)
```
Small:  0.11 μs (1KB)
Medium: 1.93 μs (32KB)  → 17.5x time for 32x data ✅ LINEAR
Large:  29.02 μs (500KB) → 15.0x time for 15.6x data ✅ LINEAR
```

### Digits Pattern (SIMD optimization)
```
Small:  0.79 μs (1KB)
Medium: 18.93 μs (32KB)  → 24.0x time for 32x data ✅ LINEAR
Large:  280.47 μs (500KB) → 14.8x time for 15.6x data ✅ LINEAR
```

### Word Boundary Pattern (fast path)
```
Small:  1.35 μs (1KB)
Medium: 34.77 μs (32KB)  → 25.8x time for 32x data ✅ LINEAR
Large:  541.03 μs (500KB) → 15.6x time for 15.6x data ✅ PERFECT LINEAR
```

### IPv4 Pattern (lazy DFA, no optimization)
```
Small:  6.54 μs (1KB)
Medium: 196.03 μs (32KB)  → 30.0x time for 32x data ✅ LINEAR
Large:  3059.62 μs (500KB) → 15.6x time for 15.6x data ✅ PERFECT LINEAR
```

## Conclusion

✅ **ALL patterns show O(n) linear scaling**
✅ **No quadratic O(n²) or exponential O(2^n) behavior**
✅ **Optimized patterns (SIMD, prefix) scale same as lazy DFA**
✅ **Rust standard sizes (1KB/32KB/500KB) verify correctness**

## Data Ratios

```
Small → Medium:  32x    (1KB → 32KB)
Medium → Large:  15.6x  (32KB → 500KB)

Expected linear scaling:
  Small → Medium:  ~32x   ✅ Observed: 17-30x
  Medium → Large:  ~15.6x ✅ Observed: 14.8-15.6x
```

## References

- [Rust regex haystacks](https://github.com/rust-lang/regex/issues/103)
- [RegexBuddy benchmark guide](https://www.regexbuddy.com/manual/benchmark.html)
- [Rust regex discussions](https://github.com/rust-lang/regex/discussions/960)

## Commands

```bash
# Run multi-size benchmark
make benchmark-sizes

# Individual sizes
./BENCHMARK_LARGE small   # 1KB, 10k iterations
./BENCHMARK_LARGE medium  # 32KB, 1k iterations
./BENCHMARK_LARGE large   # 500KB, 100 iterations
```
