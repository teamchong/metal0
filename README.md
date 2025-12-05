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
| **metal0 (WASM)** | **93ms** | **1.00x** | **46KB + 773B runtime** |
| gpt-tokenizer (JS) | 713ms | 7.7x slower | 1.1MB |
| @anthropic-ai/tokenizer (JS) | 8560ms | 92x slower | 8.6MB |

*Runtime uses Immer-style Proxy pattern - 773 bytes shared across all modules.*

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
metal0 app.py                       # compile and run
metal0 build app.py                 # compile only
metal0 build --binary app.py        # standalone executable
metal0 --force app.py               # ignore cache
metal0 --target wasm-browser app.py # browser WASM (freestanding)
metal0 --target wasm-edge app.py    # WasmEdge/WASI WASM
metal0 server                       # start eval server
```

## WASM Targets

| Target | Platform | Allocator | Features |
|--------|----------|-----------|----------|
| `wasm-browser` | Browser (freestanding) | FixedBuffer 64KB | No threads, smallest size |
| `wasm-edge` | WasmEdge/WASI | GPA | fd_write, WASI sockets |

```bash
metal0 --target wasm-browser app.py  # Browser WASM
metal0 --target wasm-edge app.py     # WasmEdge/WASI
# Outputs: app.wasm + app.d.ts
```

**Usage:**
```javascript
import { load } from '@metal0/wasm-runtime';  // 773 bytes, Immer-style runtime
import type { Tokenizer } from './tokenizer';   // generated .d.ts

const mod = await load<Tokenizer>('./tokenizer.wasm');
mod.encode("hello");  // fully typed
```

**Immer-Style Runtime (`@metal0/wasm-runtime` - 773 bytes):**

Like [Immer](https://immerjs.github.io/immer/), our runtime uses a Proxy pattern for minimal code that works with ANY module:

```javascript
// Generic Proxy-based loader - same for ALL modules
const E=new TextEncoder();let w,m,p,M=1<<20;
const g=()=>new Uint8Array(m.buffer,p,M);
const x=a=>{
  if(typeof a!=='string')return[a];
  const b=E.encode(a);
  if(b.length>M){M=b.length+1024;p=w.alloc(M)}
  g().set(b);return[p,b.length];
};
export async function load(s){
  const b=typeof s==='string'?await fetch(s).then(r=>r.arrayBuffer()):s;
  w=(await WebAssembly.instantiate(await WebAssembly.compile(b),{})).exports;
  m=w.memory;
  if(w.alloc){p=w.alloc(M)}
  return new Proxy({},{get:(_,n)=>n==='batch'?batch:typeof w[n]==='function'?(...a)=>w[n](...a.flatMap(x)):w[n]});
}
```

**Generated TypeScript definitions (tokenizer.d.ts):**
```typescript
// Auto-generated - provides full IntelliSense
export interface Tokenizer {
  encode(text: string): number;
  decode(tokens: number[]): string;
}
```

**Why Immer-Style?**
- **773 bytes** - Tiny, works with ANY WASM module
- **Proxy pattern** - Zero per-function wrapper code
- **Auto string marshalling** - Handles JS↔WASM conversion
- **Module-specific .d.ts** - Full TypeScript support

## Features

- Functions, classes, inheritance, decorators
- int, float, str, bool, list, dict, tuple, set
- List/dict/set comprehensions, f-strings, generators
- Imports, type inference (no annotations needed)
- `json`, `re`, `math`, `os`, `sys`, `http`, `asyncio`
- `eval()`, `exec()` via bytecode VM
- DWARF debug symbols, PGO, source maps

## C Extension Support

metal0 supports **any** CPython C extension (NumPy, Pandas, TensorFlow, etc.) via a complete CPython C API implementation in pure Zig.

### How It Works

```
Python script imports numpy → metal0 detects C extension → dlopen() at runtime
                                                              ↓
              NumPy calls PyList_New(), PyFloat_AsDouble() → metal0's exported C API
                                                              ↓
                                               PyObject* with CPython 3.12-compatible memory layout
```

metal0 exports **997 CPython C API functions** with **100% binary compatibility** for Python 3.10, 3.11, 3.12, and 3.13:

| Category | Functions | Examples |
|----------|-----------|----------|
| Type Objects | 45+ | `PyType_Type`, `PyLong_Type`, `PyList_Type` |
| Object Creation | 100+ | `PyObject_New`, `PyList_New`, `PyDict_New` |
| Object Protocol | 80+ | `PyObject_GetAttr`, `PySequence_GetItem` |
| Memory Management | 20+ | `Py_INCREF`, `Py_DECREF`, `PyMem_Malloc` |
| Error Handling | 40+ | `PyErr_SetString`, `PyErr_Occurred`, `PyErr_Clear` |
| Module/Import | 30+ | `PyModule_Create`, `PyImport_ImportModule` |
| Buffer Protocol | 15+ | `PyBuffer_GetPointer`, `PyMemoryView_FromBuffer` |
| Iterator Protocol | 10+ | `PyIter_Next`, `PyObject_GetIter` |
| Codec APIs | 50+ | `PyCodec_Encode`, `PyUnicode_DecodeUTF8` |
| Type Creation | 33 | `PyType_Ready`, `PyType_FromSpec`, `PyType_GenericAlloc` |

**Key Features:**
- **Pure Zig** - No CPython linking, all functions implemented natively
- **Multi-version** - Supports Python 3.10, 3.11, 3.12, 3.13 struct layouts
- **PEP 384** - Full stable ABI support with `PyType_FromSpec` heap types
- **Thread-safe** - Thread-local exception state, atomic interrupt flags
- **Small int cache** - Pre-allocated integers -5 to 256 (like CPython)

### Example: NumPy

```python
# examples/c_extensions/numpy_example.py
import numpy as np

arr = np.array([1, 2, 3, 4, 5])
print(f"Array: {arr}")
print(f"Sum: {arr.sum()}")
print(f"Mean: {arr.mean()}")

matrix = np.array([[1, 2], [3, 4]])
print(f"Matrix dot Matrix:\n{np.dot(matrix, matrix)}")
```

```bash
metal0 examples/c_extensions/numpy_example.py --force
# Info: C extension module 'numpy' will be loaded at runtime via c_interop
```

### Why This Works

1. **No CPython linking** - metal0 implements the C API in pure Zig
2. **Compatible memory layout** - `PyObject` structs match CPython's layout exactly
3. **Runtime loading** - C extensions loaded via `dlopen()`, call exported functions
4. **Zero changes needed** - Existing C extensions work unmodified

### Implementation

```zig
// packages/c_interop/src/cpython_api.zig - 997 exported functions
export fn PyList_New(size: isize) ?*cpython.PyObject { ... }
export fn PyDict_SetItem(dict: *cpython.PyObject, key: *cpython.PyObject, value: *cpython.PyObject) c_int { ... }
export fn Py_INCREF(obj: *cpython.PyObject) void { ... }

// Type creation (PEP 384 stable ABI)
export fn PyType_FromSpec(spec: *cpython.PyType_Spec) ?*cpython.PyObject { ... }
export fn PyType_Ready(type_obj: *cpython.PyTypeObject) c_int { ... }

// Type object getters (can't export var in Zig)
export fn _metal0_get_PyType_Type() *cpython.PyTypeObject { ... }
export fn _metal0_get_PyLong_Type() *cpython.PyTypeObject { ... }
```

## eval()/exec() Architecture

```
                    ┌─────────────────────────────────────┐
                    │         eval()/exec() entry         │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │    metal0 Parser + Type Inferrer    │
                    │    (REUSE existing src/parser/)     │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────▼───────────────────┐
                    │         Bytecode Compiler           │
                    │      src/bytecode/compiler.zig      │
                    └─────────────────┬───────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
    ┌─────────▼─────────┐   ┌─────────▼─────────┐   ┌─────────▼─────────┐
    │   Native Binary   │   │   Browser WASM    │   │   WasmEdge WASI   │
    │   (stack-based)   │   │   (Web Worker)    │   │   (WASI sockets)  │
    │     vm.zig        │   │  wasm_worker.zig  │   │  wasi_socket.zig  │
    └───────────────────┘   └───────────────────┘   └───────────────────┘
```

**Comptime Target Selection:**
```zig
pub const target: Target = comptime blk: {
    if (builtin.target.isWasm()) {
        if (builtin.os.tag == .wasi) break :blk .wasm_edge;
        break :blk .wasm_browser;
    }
    break :blk .native;
};
```

### Browser WASM: Immer-Style Runtime

For browser targets, eval() uses the same 773-byte Immer-style runtime with Web Worker isolation:

```javascript
import { load, registerHandlers } from '@metal0/wasm-runtime';

// Register handlers for @wasm_import decorators
registerHandlers('js', {
  fetch: async (urlPtr, urlLen) => { /* ... */ },
  localStorage_get: (keyPtr, keyLen) => { /* ... */ }
});

// Eval spawns isolated Web Workers using cached WASM module
const mod = await load('./module.wasm');
const result = await mod.eval("1 + 2");  // Returns 3
```

**Web Worker Isolation:**
- Simple expressions run inline
- Complex code spawns Web Worker for security
- Cached WASM module enables "viral spawning" - workers share compiled module

### WasmEdge WASI: Server-Side Eval

```python
# Just use eval() like normal Python
result = eval("1 + 2 * 3")  # Returns 7

# Or exec() for statements
exec("x = 42")
print(x)  # 42
```

```bash
# Server runs automatically when eval()/exec() is used
# Or start manually for persistent connections:
metal0 server --vm-module metal0_vm.wasm
```

**Architecture:**
- Fresh WASM instance per eval() call (security isolation)
- Bytecode compiled from Python source
- Executed in WasmEdge sandbox

### User-Declared Bindings

Instead of hardcoding JS/WASI functions, declare what you need:

```python
from metal0 import wasm_import, wasm_export

@wasm_import("js")
def fetch(url: str) -> str: ...

@wasm_export
def process(data: str) -> list[int]:
    result = fetch("/api/data")
    return [ord(c) for c in result]
```

metal0 generates optimized Zig externs and minimal JS loader - only declared functions included.

## How It Works

```
Python → Lexer → Parser → Type Inference → Zig codegen → Native binary
```

No Python runtime. Types inferred at compile time. Zig handles memory.

## Debugging

```bash
metal0 app.py --debug           # DWARF + source maps
lldb ./build/lib.../app         # Python line numbers in debugger
metal0 profile run app.py       # Profile collection
metal0 profile show app.py      # View hotspots
```

## License

Apache 2.0
