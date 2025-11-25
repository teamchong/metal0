# PyAOT Benchmark Results

**Date:** 2025-01-15
**Platform:** macOS ARM64 (Darwin 25.1.0)
**Tool:** hyperfine v1.19.0
**Python:** 3.12.10
**Zig:** 0.15.2
**PyAOT:** v0.1.0-alpha

---

## Quick Start

Run all benchmarks:
```bash
./benchmarks/run_benchmarks.sh
```

Run NumPy benchmarks (with Numba comparison):
```bash
./benchmarks/run_numpy_benchmarks.sh
```

---

## Summary

| Benchmark | CPython | PyPy | PyAOT | Best Speedup |
|:---|---:|---:|---:|---:|
| **Fibonacci(43)** | 51.7 s | TBD | 3.7 s | **13.91x faster** 🚀 |
| **Loop Sum (1B)** | 58.4 s | TBD | 2.1 s | **27.23x faster** 🚀 |
| **String Concat** | TBD | TBD | TBD | TBD |
| **JSON Parse** | TBD | TBD | TBD | TBD |
| **NumPy Operations** | TBD | TBD | TBD | TBD |

---

## Benchmark Details

### 1. Fibonacci (Recursive)

Recursive fibonacci calculation with heavy function call overhead.

**Code:** `benchmarks/fibonacci.py`
```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result = fibonacci(43)
print(result)  # 433494437
```

**Run:**
```bash
hyperfine --warmup 2 --runs 3 \
  "python benchmarks/fibonacci.py" \
  "pypy3 benchmarks/fibonacci.py" \
  "pyaot benchmarks/fibonacci.py"
```

**Results:**
```
Benchmark 1: python benchmarks/fibonacci.py
  Time (mean ± σ):     51.747 s ±  0.207 s
  Range (min … max):   51.561 s … 51.971 s    3 runs

Benchmark 2: pypy3 benchmarks/fibonacci.py
  Time (mean ± σ):     TBD

Benchmark 3: pyaot benchmarks/fibonacci.py
  Time (mean ± σ):      3.720 s ±  0.005 s
  Range (min … max):    3.717 s …  3.725 s    3 runs

Summary: pyaot ran 13.91 ± 0.06 times faster than python
```

**Why PyAOT wins:**
- Direct function calls (no interpreter overhead)
- Native i64 in registers (no PyLongObject allocations)
- Zero dynamic dispatch
- AOT compilation vs JIT warmup

---

### 2. Loop Sum (1 billion iterations)

Pure Python loop with integer arithmetic.

**Code:** `benchmarks/loop_sum.py`
```python
total = 0
for i in range(1000000000):
    total = total + i
print(total)
```

**Results:**
```
Benchmark 1: python benchmarks/loop_sum.py
  Time (mean ± σ):     58.355 s ±  1.607 s
  Range (min … max):   57.301 s … 60.205 s    3 runs

Benchmark 2: pyaot benchmarks/loop_sum.py
  Time (mean ± σ):      2.143 s ±  0.039 s
  Range (min … max):    2.119 s …  2.188 s    3 runs

Summary: pyaot ran 27.23 ± 0.90 times faster
```

---

### 3. String Concatenation

String operations in tight loop.

**Code:** `benchmarks/string_concat.py`
```python
a = "Hello"
b = "World"
c = "PyAOT"
d = "Compiler"

result = ""
for i in range(400000000):
    result = a + b + c + d

print(result)
```

**Run:**
```bash
hyperfine --warmup 2 --runs 3 \
  "python benchmarks/string_concat.py" \
  "pypy3 benchmarks/string_concat.py" \
  "pyaot benchmarks/string_concat.py"
```

---

### 4. JSON Parsing

Parse small JSON objects repeatedly.

**Code:** `benchmarks/json_bench.py`
```python
import json

data = '{"id": 123, "name": "test", "active": true, "score": 95.5}'

for _ in range(10_000_000):
    obj = json.loads(data)

print("Done")
```

**Run:**
```bash
hyperfine --warmup 2 --runs 3 \
  "python benchmarks/json_bench.py" \
  "pypy3 benchmarks/json_bench.py" \
  "pyaot benchmarks/json_bench.py"
```

---

### 5. NumPy Operations

NumPy array operations.

**Code:** `benchmarks/numpy_bench.py`
```python
import numpy as np

for _ in range(100):
    a = np.arange(1_000_000, dtype=np.float64)
    b = np.arange(1_000_000, dtype=np.float64)
    c = a + b
    d = np.sin(c)
    e = np.sqrt(d * d + 1)
    result = np.mean(e)

print(f"Result: {result}")
```

**Run:**
```bash
# Compare CPython+NumPy vs PyPy+NumPy vs PyAOT+NumPy
./benchmarks/run_numpy_benchmarks.sh
```

**With Numba:** `benchmarks/numpy_numba_bench.py`
- Uses `@jit(nopython=True)` decorator
- Compares CPython+Numba vs PyAOT+NumPy

---

## Methodology

### Benchmark Design

**60-second rule:**
- All benchmarks run ~60 seconds on CPython
- Ensures statistical significance
- Eliminates startup time bias
- Proves sustained performance

**Hyperfine:**
```bash
hyperfine --warmup 2 --runs 3 "python X" "pypy3 X" "pyaot X"
```

- 2 warmup runs (eliminate cold start)
- 3 measured runs (statistical reliability)
- Low standard deviation required

### Compilation

**PyAOT:**
```bash
make install  # Builds with -O ReleaseFast
pyaot script.py
```

**System:**
- **OS:** macOS 14.x (Darwin 25.1.0)
- **CPU:** Apple Silicon (ARM64)
- **Zig:** 0.15.2
- **Python:** 3.12.10
- **PyPy:** 7.3.x (if installed)
- **Numba:** Latest (if installed)

---

## Performance Characteristics

**PyAOT excels at:**
- Recursive algorithms (13.91x)
- Computational loops (27.23x)
- CPU-bound tasks
- Integer arithmetic

**Performance range:** 13-27x faster than CPython

**Why PyAOT is fast:**
- AOT compilation to native code
- No interpreter overhead
- Native integers in registers
- Zero dynamic dispatch
- No GC pauses

---

## Installing Comparison Tools

**PyPy (optional):**
```bash
brew install pypy3
```

**Numba (optional, for NumPy benchmarks):**
```bash
pip install numba
# or
uv pip install numba
```

**Hyperfine (required):**
```bash
brew install hyperfine
```

---

## License

Apache 2.0
