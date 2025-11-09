# Zyth Performance Benchmarks

## Summary

| Benchmark | Zyth | Python | Speedup |
|:---|---:|---:|---:|
| **Fibonacci(35)** | 28.2 ms | 804.5 ms | **28.56x faster** 🚀 |
| **String Concat** | 1.9 ms | 23.6 ms | **12.24x faster** ⚡ |

---

## 1. Fibonacci (Recursive Integer Operations)

**Test:** Recursive fibonacci calculation
```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result = fibonacci(35)  # Result: 9227465
```

### Results

| Engine | Mean | Min | Max | Relative |
|:---|---:|---:|---:|---:|
| **Zyth (compiled)** | 28.2 ms | 26.8 ms | 30.9 ms | **1.00x** (baseline) |
| Python (CPython) | 804.5 ms | 800.3 ms | 809.7 ms | 28.56x slower |

### Summary

🚀 **Zyth is 28.56x faster than Python for recursive fibonacci**

### Analysis

The 28x speedup comes from:

1. **No function call overhead** - Direct function calls vs Python's CALL_FUNCTION opcode
2. **No interpreter loop** - Compiled machine code vs bytecode interpretation
3. **Register-based operations** - CPU registers vs Python's stack machine
4. **No integer object allocation** - Native i64 vs PyLongObject heap allocations

---

## 2. String Concatenation

**Test:** Simple string concatenation of 4 strings
```python
a = "Hello"
b = "World"
c = "Zyth"
d = "Compiler"
result = a + b + c + d
```

### Results

| Engine | Mean | Min | Max | Relative |
|:---|---:|---:|---:|---:|
| **Zyth (compiled)** | 1.9 ms | 0.9 ms | 4.3 ms | **1.00x** (baseline) |
| Python (CPython) | 23.6 ms | 21.3 ms | 44.3 ms | 12.24x slower |

### Summary

⚡ **Zyth is 12.24x faster than Python for string concatenation**

### Analysis

The 12x speedup comes from:

1. **No interpreter overhead** - Compiled to native code
2. **Efficient memory management** - Zig's allocator vs Python's GC
3. **No dynamic type checking** - Types known at compile time
4. **Direct system calls** - No Python runtime layer

---

## Methodology

- **Tool:** hyperfine v1.19.0
- **Warmup:** 3-5 runs
- **Platform:** macOS (ARM64)
- **Compiler:** Zig 0.15.2 with `-O ReleaseFast`
- **Date:** 2025-11-09

---

## Next Steps

- [ ] Benchmark list operations
- [ ] Benchmark mixed workloads
- [ ] Compare with PyPy
- [ ] Add memory usage comparison
