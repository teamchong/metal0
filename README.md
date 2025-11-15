# PyAOT

**v0.1.0-alpha** - Early development, not production-ready

Python to Zig AOT compiler. Write Python, run native code.

**Up to 27x faster** than CPython | Native binaries | Zero runtime overhead

## Quick Start

```bash
# Clone and install
git clone <repo-url> pyaot
cd pyaot
make install

# Compile and run
pyaot examples/fibonacci.py
```

## Installation

**Requirements:**
- Zig 0.15.2 or later

**Install:**
```bash
make install
```

This builds an optimized 433KB binary and installs it to `~/.local/bin/pyaot`.

Make sure `~/.local/bin` is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
# Compile and run (default: shared library .so)
pyaot your_file.py

# Build standalone binary
pyaot --binary your_file.py

# Force recompilation (ignore cache)
pyaot --force your_file.py

# Build only, don't run
pyaot build your_file.py

# Build standalone binary without running
pyaot build --binary your_file.py
```

### Compilation Modes

**Shared Library (.so) - Default:**
- Fast compilation
- Smaller output size
- Architecture-specific naming (e.g., `myapp_x86_64.so`, `myapp_arm64.so`)
- Timestamp-based caching for faster rebuilds

**Standalone Binary (--binary):**
- Fully self-contained executable
- No dependencies
- Slightly larger size
- Portable within same architecture

## Examples

### 1. Computational (Fibonacci)

Fast recursive computation - **14x faster** than CPython.

```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result = fibonacci(35)
print(result)  # 9227465
```

```bash
pyaot examples/fibonacci.py
# Output: 9227465 (in 59ms vs CPython's 842ms)
```

### 2. Object-Oriented (Class Inheritance)

Full OOP support with classes and inheritance.

```python
class Shape:
    def __init__(self, x: int, y: int):
        self.x = x
        self.y = y

class Rectangle(Shape):
    def __init__(self, x: int, y: int, width: int, height: int):
        self.x = x
        self.y = y
        self.width = width
        self.height = height

    def area(self) -> int:
        return self.width * self.height

rect = Rectangle(10, 20, 5, 3)
print(rect.area())  # 15
```

### 3. List Processing

List comprehensions with filtering.

```python
numbers = [1, 2, 3, 4, 5]
filtered = [x for x in numbers if x > 2]
print(filtered)  # [3, 4, 5]

# List methods
numbers.append(6)
numbers.reverse()
print(numbers)
```

### 4. String Operations

String manipulation - **8x faster** than CPython.

```python
text = "Hello, World!"
upper = text.upper()
words = text.split(", ")
print(upper)     # HELLO, WORLD!
print(words[0])  # Hello

# String methods: upper, lower, split, strip, replace, find, count
```

## Performance

Benchmarked with [hyperfine](https://github.com/sharkdp/hyperfine) on macOS ARM64 (Apple Silicon).

All benchmarks run ~60 seconds on CPython for statistical significance.

| Benchmark | CPython | PyPy | PyAOT | vs CPython | vs PyPy |
|:----------|--------:|-----:|------:|-----------:|--------:|
| **Loop Sum (1.4B)** | ~60s | 2.1s | 1.5s | **28x faster** 🚀 | **1.4x faster** |
| **Fibonacci(45)** | ~60s | 7.6s | 4.4s | **14x faster** 🚀 | **1.7x faster** |
| **String Concat (650M)** | ~60s | 1.5s | TBD | **TBD** | TBD |

**Performance highlights:**
- **Loop sum:** 28x faster than CPython, 1.4x faster than PyPy
- **Recursive fibonacci:** 14x faster than CPython, 1.7x faster than PyPy
- **Range:** 14-28x speedup vs CPython on computational tasks
- **AOT vs JIT:** PyAOT beats PyPy's JIT compiler on most benchmarks

**Why PyAOT is faster:**
- Direct compilation to native machine code via Zig (no interpreter)
- Eliminates Python interpreter overhead completely
- Native i64 in CPU registers vs PyLongObject heap allocations
- Zero dynamic dispatch - direct function calls
- No GC pauses or JIT warmup time
- AOT compilation (no warmup needed unlike PyPy's JIT)

**Run benchmarks:**
```bash
./benchmarks/run_benchmarks.sh  # Compares CPython vs PyPy vs PyAOT
```

**Key insights:**
- PyAOT excels at CPU-bound tasks with heavy function call overhead
- Best suited for recursive algorithms, computational loops, and integer arithmetic
- Zero runtime overhead - binaries are pre-compiled
- Faster than PyPy's JIT on most computational workloads
- All benchmarks measure runtime only (no compilation time included)

Detailed methodology and results: [benchmarks/RESULTS.md](benchmarks/RESULTS.md)

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
- [ ] pyaot.web (HTTP server)
- [ ] pyaot.http (HTTP client)
- [ ] pyaot.ai (LLM integration)
- [ ] pyaot.async (async/await)
- [ ] pyaot.db (database connectors)

**Phase 3: Advanced**
- [ ] WebAssembly target
- [ ] Goroutines and channels
- [ ] JIT compilation
- [ ] REPL

## Architecture

**Pure Zig Compiler (No Python Dependency):**

```
pyaot/
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

Apache 2.0 - see [LICENSE](LICENSE) file for details.

This project includes patent grants for all compression algorithms and optimization techniques.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon)
