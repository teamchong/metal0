# Zyth

**v0.1.0-alpha** - Early development, not production-ready

Python to Zig AOT compiler. Write Python, run native code.

**Up to 41x faster** than CPython | Native binaries | Zero runtime overhead

## Quick Start

```bash
# Clone and install
git clone <repo-url> zyth
cd zyth
make install

# Compile and run
zyth examples/fibonacci.py
```

## Installation

**Requirements:**
- Zig 0.15.2 or later

**Install:**
```bash
make install
```

This builds an optimized 433KB binary and installs it to `~/.local/bin/zyth`.

Make sure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
# Compile and run
zyth your_file.py

# Build without running
zyth build your_file.py

# Custom output path
zyth build your_file.py /tmp/output
```

## Example

**Input (examples/fibonacci.py):**
```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result = fibonacci(10)
print(result)
```

**Compile and run:**
```bash
zyth examples/fibonacci.py
# Output: 55

# Or build without running
zyth build examples/fibonacci.py
./bin/fibonacci
# Output: 55
```

## Performance

| Benchmark | CPython | Zyth | Speedup |
|:---|---:|---:|---:|
| **Loop sum (1M)** | 65.4 ms | 1.6 ms | **41.40x faster** 🔥 |
| **Fibonacci(35)** | 804.5 ms | 28.2 ms | **28.56x faster** 🚀 |
| **Fibonacci(40)** | 12.3 s | 886 ms | **13.87x faster** 🚀 |
| **List methods** | 22.1 ms | 1.5 ms | **14.89x faster** ⚡ |
| **List operations** | 22.3 ms | 1.6 ms | **13.98x faster** ⚡ |
| **String concat** | 23.6 ms | 1.9 ms | **12.24x faster** ⚡ |

**Benchmarked with [hyperfine](https://github.com/sharkdp/hyperfine)** on macOS ARM64.
**Note:** Zyth binaries are pre-compiled - benchmarks measure **runtime only**, not compile time.

Raw results: [loop_sum_results.md](benchmarks/loop_sum_results.md) · [fibonacci_results.md](benchmarks/fibonacci_results.md) · [list_methods_results.md](benchmarks/list_methods_results.md) · [list_ops_results.md](benchmarks/list_ops_results.md) · [string_results.md](benchmarks/string_results.md)

## Features

### ✅ Implemented (101/142 tests passing - 71.1%)

**Core Language:**
- ✅ Function definitions with return values
- ✅ Class inheritance with `super()`
- ✅ Control flow (if/else, while, for loops)
- ✅ Variable reassignment detection (var vs const)
- ✅ Tuples with element type tracking
- ✅ Import/module system (6/8 tests passing)
- ✅ Exception handling (`try/except` - basic support)

**Data Types:**
- ✅ Lists (literals, indexing, slicing, comprehensions)
- ✅ Strings (literals, slicing, concatenation)
- ✅ Dicts (literals, key access)
- ✅ Integers (primitives and PyObject)

**Built-in Functions (7 total):**
- ✅ `range(start, end, step)` - Iterate over numeric ranges
- ✅ `enumerate(iterable)` - Loop with index
- ✅ `zip(*iterables)` - Parallel iteration
- ✅ `len(obj)` - Length of strings, lists, dicts
- ✅ `min(*args)` - Minimum of values
- ✅ `max(*args)` - Maximum of values
- ✅ `sum(iterable)` - Sum of numeric list

**Built-in Methods (19 total):**
- ✅ String: `upper()`, `lower()`, `split()`, `strip()`, `replace()`, `find()`, `count()`
- ✅ List: `append()`, `pop()`, `extend()`, `remove()`, `reverse()`, `count()`, `index()`, `insert()`, `clear()`, `copy()`
- ✅ Dict: `get()`, `keys()`, `values()`, `items()`, `copy()`

**Advanced Features:**
- ✅ List comprehensions with filters
- ✅ List/string slicing with step (e.g., `nums[1:5:2]`)
- ✅ Mixed type operations (primitive + PyObject)
- ✅ Automatic memory management (reference counting)
- ✅ Timestamp-based build cache (3x faster compilation)
- ✅ Debug builds with memory leak detection

### 📋 Roadmap

**Phase 1: Core Completeness**
- [ ] File I/O operations
- [ ] String formatting (f-strings)
- [ ] More dict methods
- [ ] Decorators
- [ ] Generators

**Phase 2: Standard Library**
- [ ] zyth.web (HTTP server)
- [ ] zyth.http (HTTP client)
- [ ] zyth.ai (LLM integration)
- [ ] zyth.async (async/await)
- [ ] zyth.db (database connectors)

**Phase 3: Advanced**
- [ ] WebAssembly target
- [ ] Goroutines and channels
- [ ] JIT compilation
- [ ] REPL

## Architecture

**Pure Zig Compiler (No Python Dependency):**

```
zyth/
├── src/                      # Zig compiler (3 phases)
│   ├── main.zig             # Entry point & CLI
│   ├── lexer.zig            # Phase 1: Tokenization
│   ├── parser.zig           # Phase 2: AST construction
│   ├── codegen.zig          # Phase 3: Zig code generation
│   ├── compiler.zig         # Zig compilation wrapper
│   └── ast.zig              # AST node definitions
├── packages/runtime/src/     # Runtime library
│   ├── runtime.zig          # PyObject & memory management
│   ├── pystring.zig         # String methods
│   ├── pylist.zig           # List methods
│   ├── dict.zig             # Dict methods
│   └── pyint.zig            # Integer wrapping
├── examples/                 # Demo programs
├── tests/                    # Integration tests (pytest)
├── build.zig                 # Zig build configuration
└── Makefile                  # Simple build/install
```

**Compilation Pipeline:**
1. **Lexer**: Python source → Tokens
2. **Parser**: Tokens → AST (native Zig structures)
3. **Codegen**: AST → Zig source code
4. **Zig Compiler**: Zig code → Native binary

## Development

```bash
# Build debug binary (for development)
make build

# Build optimized binary
make build-release

# Install optimized binary
make install

# Run tests (requires pytest)
pytest

# Zig runtime tests
make test-zig

# Clean build artifacts
make clean
```

## Requirements

- **Compilation**: Zig 0.15.2+ only
- **Testing** (optional): Python 3.10+ with pytest

## Documentation

See `docs/` for detailed documentation:
- [Architecture](docs/ARCHITECTURE.md)
- [Compilation Flow](docs/COMPILATION_FLOW.md)
- [Monorepo Structure](docs/MONOREPO_STRUCTURE.md)

## Status

**v0.1.0-alpha** - Active Development 🚧

- **Test Coverage:** 101/142 tests passing (71.1%) ⬆ +23 tests
- **Memory Safety:** Debug builds with automatic leak detection ✅
- **Build Cache:** Timestamp-based compilation cache ✅
- **Core Features:** Functions, classes, slicing, comprehensions, built-ins ✅
- **Recent Additions:** 7 built-in functions (range, enumerate, zip, len, min, max, sum)
- **In Progress:** Boolean operators, exception edge cases, variable tracking

**Not Production Ready:**
- Limited Python compatibility (subset of language)
- Some advanced features still in development
- API subject to breaking changes
- No PyPI package yet

**Progress:** Active development with frequent feature additions. Production release planned for v1.0.

## License

[Add license]

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon)
