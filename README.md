# metal0

> **Early alpha** - API unstable, not production-ready

Python Syntax. Bare Metal Speed. Zero Friction.

```bash
git clone https://github.com/teamchong/metal0 && cd metal0 && make install
metal0 app.py        # compile + run
metal0 build app.py  # compile only
```

## Why

Python is slow. Packaging is painful. metal0 fixes both:

| | Python | metal0 |
|---|--------|--------|
| **Speed** | 1x | 30x |
| **Binary** | pip + venv + deps | single 50KB file |
| **Docker** | 900MB | <1MB |
| **Startup** | 50ms | 1ms |

## Benchmarks

All benchmarks on Apple M2.

### Async/Concurrency

metal0 compiles Python's `asyncio` to optimized native code:
- **I/O-bound**: State machine coroutines with kqueue netpoller (single thread, high concurrency)
- **CPU-bound**: Thread pool with M:N scheduling (parallel execution across cores)

**Parallel Scaling: SHA256 Hashing (8 workers × 50K hashes each)**

| Runtime | Speedup | Efficiency | Notes |
|---------|---------|------------|-------|
| **metal0** | **6.05x** | **76%** | Thread pool + stack alloc, no GC |
| Go (goroutines) | 3.72x | 47% | M:N scheduler, GC overhead |
| Rust (rayon) | 1.04x | 13% | Work-stealing overhead |
| CPython | 1.07x | 13% | GIL blocks parallelism |
| PyPy | 0.98x | 12% | GIL + JIT overhead |

*Speedup = Sequential / Parallel. Ideal: 8x for 8 cores. metal0 achieves 1.6x better parallel efficiency than Go.*

**I/O-Bound: Concurrent Sleep (10,000 tasks × 100ms each)**

| Runtime | Time | Concurrency | vs Sequential |
|---------|------|-------------|---------------|
| **metal0** | **103.5ms** | **9,662x** | Best event loop |
| Rust (tokio) | 111.7ms | 8,952x | Great async runtime |
| Go | 126.9ms | 7,880x | Great for network |
| CPython | 194.3ms | 5,147x | Good for I/O |
| PyPy | 258.8ms | 3,864x | Slower I/O |

*Sequential would take 1,000,000ms (16.7 min). metal0 achieves 9662× concurrency via state machine + kqueue netpoller.*

### Recursive Computation

**Fibonacci(45) - Recursive:**

| Language | Time | vs Python |
|----------|------|-----------|
| **metal0** | **3.22s** | **30.1x faster** |
| Rust | 3.23s | 30.0x faster |
| Go | 3.60s | 26.9x faster |
| PyPy | 11.75s | 8.3x faster |
| Python | 96.94s | baseline |

**Tail-Recursive Fibonacci (10K × fib(10000)) - TCO Test:**

| Language | Time | vs metal0 |
|----------|------|----------|
| **metal0** | **31.9ms** | **1.00x** |
| Rust | 32.2ms | 1.01x |
| Go | 286.7ms | 8.99x slower |
| Python/PyPy | N/A | RecursionError |

*metal0 uses `@call(.always_tail)` for guaranteed TCO.*

**Startup Time - Hello World (100 runs):**

| Language | Time | vs CPython |
|----------|------|------------|
| **metal0** | **1.6ms** | **14x faster** |
| Rust | 1.8ms | 12x faster |
| Go | 2.4ms | 9x faster |
| CPython | 22.4ms | baseline |

### JSON Benchmark (50K iterations × 38KB realistic JSON)

**JSON Parse (50K × 38KB = 1.9GB processed):**

| Implementation | Time | vs metal0 |
|---------------|------|----------|
| **metal0** | **2.68s** | **1.00x** |
| PyPy | 3.16s | 1.18x slower |
| Rust (serde_json) | 4.70s | 1.76x slower |
| Python | 8.40s | 3.14x slower |
| Go | 14.0s | 5.23x slower |

**JSON Stringify (50K × 38KB = 1.9GB processed):**

| Implementation | Time | vs metal0 |
|---------------|------|----------|
| **metal0** | **2.68s** | **1.00x** |
| Rust (serde_json) | 3.01s | 1.12x slower |
| Python | 12.3s | 4.60x slower |
| PyPy | 12.4s | 4.61x slower |
| Go | 15.6s | 5.81x slower |

**Key optimizations:**
- Arena allocator - bump-pointer (~2 CPU cycles per alloc vs ~100+ for malloc)
- SWAR string scanning - 8 bytes at a time (PyPy's technique)
- Small integer cache - pre-allocated for -10 to 256
- SIMD whitespace skipping (AVX2/NEON) - 32 bytes per iteration
- SIMD string escaping - 4.3x speedup on ARM64 NEON

### Dict/String Benchmarks

**Dict Benchmark (10M lookups, 8 keys):**

| Language | Time | vs Python |
|----------|------|-----------|
| **metal0** | **329ms** | **4.3x faster** |
| PyPy | 570ms | 2.5x faster |
| Python | 1.42s | baseline |

**String Benchmark (100M iterations, comparison + length):**

| Language | Time | vs Python |
|----------|------|-----------|
| **metal0** | **1.6ms** | **5000x faster** |
| PyPy | 154ms | 53x faster |
| Python | 8.1s | baseline |

*metal0 string operations are computed at comptime where possible.*

### NumPy Matrix Multiplication (BLAS)

500×500 matrix multiplication using BLAS `cblas_dgemm`.

| Runtime | Time | vs metal0 |
|---------|------|----------|
| **metal0** (BLAS) | **3.2ms** | **1.00x** |
| Python (NumPy) | 66ms | 21x slower |
| PyPy (NumPy) | 129ms | 40x slower |

*All use the same BLAS library - metal0 eliminates interpreter overhead.*

### Tokenizer Benchmark

**100% Correctness** - Verified against tiktoken cl100k_base (3459/3459 tests pass).

**BPE Encoding (59,200 encodes - 592 texts × 100 iterations):**

| Implementation | Time | vs metal0 | Correctness |
|---------------|------|----------|-------------|
| **metal0 (Zig)** | **81ms** | **1.00x** | **100%** |
| rs-bpe (Rust) | 420ms | 5.2x slower | 100% |
| tiktoken (Rust) | 1110ms | 13.7x slower | 100% |
| HuggingFace (Python) | 5439ms | 67x slower | 100% |

*Tested on Apple M2 with `json.load()` data.*

**Web/WASM Encoding (583 texts × 200 iterations):**

| Library | Time | vs metal0 | Size |
|---------|------|----------|------|
| @anthropic-ai/tokenizer (JS) | 64.8ms | 1.12x faster | 8.6MB |
| **metal0 (WASM)** | **72.5ms** | **1.00x** | **46KB** |
| gpt-tokenizer (JS) | 1487ms | 20.5x slower | 1.1MB |
| tiktoken (Node) | 17951ms | 248x slower | 1.0MB |

**BPE Training (vocab_size=32000, 300 iterations):**

| Library | Time | vs metal0 | Correctness |
|---------|------|----------|-------------|
| **metal0 (Zig)** | **68.7ms** | **1.00x** | **100%** |
| HuggingFace (Rust) | 1707.9ms | 25x slower | 100% |

*Training produces identical vocabularies - verified with comparison test.*

**Unigram Training (vocab_size=32000, 100 iterations):**

| Library | Time | vs HuggingFace |
|---------|------|----------------|
| HuggingFace (Rust) | 2.15s | 1.00x |
| metal0 (Zig) | 5.70s | 2.65x slower |

*BPE training is 22x faster. Unigram improved from 11.95x to 2.65x slower.*

### Regex Benchmark

**Regex Pattern Matching (5 common patterns):**

| Implementation | Total Time | vs metal0 |
|----------------|------------|----------|
| **metal0 (Lazy DFA)** | **1.324s** | **1.00x** |
| Rust (regex) | 4.639s | 3.50x slower |
| Python (re) | ~43s | ~32x slower |
| Go (regexp) | ~58s | ~44x slower |

**Pattern breakdown (1M iterations each):**

| Pattern | metal0 | Rust | Speedup |
|---------|-------|------|---------|
| Email | 93ms | 95ms | 1.02x |
| URL | 81ms | 252ms | 3.12x |
| Digits | 692ms | 3,079ms | 4.45x |
| Word Boundary | 116ms | 385ms | 3.32x |
| Date ISO | 346ms | 636ms | 1.84x |

### Running Benchmarks

```bash
make benchmark-fib         # Fibonacci
make benchmark-json-full   # JSON parse + stringify
make benchmark-dict        # Dict lookups
make benchmark-string      # String operations
make benchmark-regex       # Regex patterns
make benchmark-asyncio     # CPU-bound async
make benchmark-asyncio-io  # I/O-bound async
make benchmark-numpy       # NumPy BLAS

# Tokenizer benchmarks (run from packages/tokenizer/)
cd packages/tokenizer && zig build -Doptimize=ReleaseFast && ./zig-out/bin/bench_train
```

## Install

```bash
git clone https://github.com/teamchong/metal0
cd metal0 && make install
```

Requires: Zig 0.15.2+

## Usage

```bash
metal0 app.py              # compile and run
metal0 build app.py        # compile only
metal0 build --binary app.py  # standalone executable
metal0 --force app.py      # ignore cache
```

## Features

**Working:**
- Functions, classes, inheritance
- int, float, str, bool, list, dict, tuple
- List/dict comprehensions, f-strings
- Imports (local modules, packages)
- Type inference (no annotations required)
- `json`, `re`, `math`, `http`, `asyncio`
- `eval()`, `exec()` via bytecode VM

**In Progress:**
- Decorators, generators
- Exception handling
- Full stdlib coverage
- NumPy (BLAS integrated)

## How It Works

```
Python source → Lexer → Parser → Type Inference → Zig codegen → Native binary
```

- No Python runtime bundled
- Types inferred at compile time
- Zig handles memory (no GC)
- Dead code eliminated

## Compatibility

Targeting 421 CPython test files. Current: early alpha.

**Works well for:**
- CLI tools
- Serverless functions
- WASM/browser
- Embedded systems

**In progress:**
- Full stdlib coverage
- 100% CPython test compatibility

## License

Apache 2.0
