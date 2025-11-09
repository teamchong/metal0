# Benchmark Results

## Summary

| Benchmark | CPython | Zyth | Speedup |
|:---|---:|---:|---:|
| **fibonacci(35)** | 804.5 ms | 28.2 ms | **28.56x** 🚀 |
| **String concat** | 23.6 ms | 1.9 ms | **12.24x** ⚡ |

## Details

### Fibonacci (Recursive Integer Operations)

Recursive calculation of fibonacci(35) = 9227465

- **Zyth:** 28.2 ms ± 0.9 ms
- **Python:** 804.5 ms ± 2.9 ms
- **Speedup:** 28.56x faster

The speedup comes from:
- No function call overhead
- No interpreter loop
- Native register operations
- No integer object allocation

Raw data: [fibonacci_results.md](fibonacci_results.md)

### String Concatenation  

Concatenating 4 strings: `a + b + c + d`

- **Zyth:** 1.9 ms ± 0.5 ms
- **Python:** 23.6 ms ± 2.5 ms
- **Speedup:** 12.24x faster

The speedup comes from:
- No interpreter overhead
- Efficient memory management
- No dynamic type checking
- Direct system calls

Raw data: [results.md](results.md)

## Methodology

- **Tool:** hyperfine v1.19.0
- **Warmup:** 3-5 runs
- **Platform:** macOS (ARM64)
- **Compiler:** Zig 0.15.2 with `-O ReleaseFast`
- **Date:** 2025-11-09
