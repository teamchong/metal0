# metal0

> **Early alpha** - API unstable, not production-ready

AOT Python compiler. Native speed. Single binary.

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

All benchmarks on Apple M2. [Full methodology](benchmarks/RESULTS.md).

### Compute

| Benchmark | metal0 | Rust | Go | PyPy | Python |
|-----------|--------|------|-----|------|--------|
| fib(45) recursive | **3.2s** | 3.2s | 3.6s | 11.8s | 97s |
| JSON parse 1.9GB | **2.7s** | 4.7s | 14s | 3.2s | 8.4s |
| JSON stringify 1.9GB | **2.7s** | 3.0s | 15.6s | 12.4s | 12.3s |
| Regex 5 patterns | **1.3s** | 4.6s | ~58s | - | ~43s |
| Dict 10M lookups | **329ms** | - | - | 570ms | 1.4s |

### Async

| Benchmark | metal0 | Rust | Go | Python |
|-----------|--------|------|-----|--------|
| 10K concurrent sleeps | **103ms** | 112ms | 127ms | 194ms |
| 8-core SHA256 parallel | **6.05x** | 1.04x | 3.72x | 1.07x |

### Tokenizers

Faster than HuggingFace (Rust) on all algorithms:

| Algorithm | metal0 | HuggingFace | Speedup |
|-----------|--------|-------------|---------|
| BPE encode | 2.5s | 44s | 18x |
| BPE train | 1.1s | 26.7s | 24x |
| Unigram train | 108ms | 263ms | 2.4x |

WASM: **178x faster** than tiktoken, **46KB** vs 1MB.

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

**Not ready for:**
- Dynamic metaprogramming
- C extension ecosystem (partial)

## License

Apache 2.0
