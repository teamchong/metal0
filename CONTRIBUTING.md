# Contributing to metal0

Thanks for your interest in contributing! metal0 is an early-stage project, and we welcome contributions of all kinds.

## Project Status

metal0 is in **early alpha**. This means:
- The codebase is evolving rapidly
- APIs and internals may change without notice
- Some areas are well-tested, others are experimental
- Documentation is sparse

This is actually a great time to contribute - your input can shape the project's direction.

## Ways to Contribute

### Good First Contributions

- **Bug reports** - Found something that doesn't work? Open an issue with a minimal repro
- **Test cases** - Add Python files that should compile but don't (or shouldn't but do)
- **Documentation** - README improvements, code comments, examples
- **Typo fixes** - Small PRs welcome

### Intermediate Contributions

- **CPython compatibility** - Help pass more tests from `tests/cpython/`
- **Error messages** - Improve compiler error clarity
- **Runtime functions** - Implement missing Python builtins in `packages/runtime/`

### Advanced Contributions

- **Codegen improvements** - Work on `src/codegen/native/`
- **Type inference** - Improve `src/analysis/`
- **New features** - Discuss in an issue first

## Development Setup

### Prerequisites

- **Zig 0.15.x** - Install from [ziglang.org/download](https://ziglang.org/download/)
  - The project tracks Zig master; currently tested with **0.15.2**
  - Zig 0.14.x may work but is not guaranteed
- **macOS or Linux** - Windows support is limited
- **hyperfine** (optional) - For running benchmarks (`brew install hyperfine`)

### Building

```bash
# Clone and build
git clone https://github.com/paiml/metal0
cd metal0

# Debug build (fast iteration)
zig build
# or
make build

# Release build + install to ~/.local/bin
make install
```

### Running Tests

The **Makefile is the source of truth** for test commands:

```bash
# Quick validation (recommended during development)
make test              # Runs: build + test-unit

# Individual test suites
make test-unit         # Unit tests via `metal0 test tests/unit`
make test-integration  # Integration tests via `metal0 test tests/integration`
make test-cpython      # CPython compatibility tests

# Everything (slow)
make test-all          # Runs: test-unit + test-integration + test-cpython
```

To run a specific Python file:
```bash
./zig-out/bin/metal0 path/to/test.py           # Compile and run
./zig-out/bin/metal0 build path/to/test.py     # Compile only
```

### Debugging

```bash
# View generated Zig code (useful for debugging codegen issues)
cat .metal0/cache/metal0_main_*.zig

# The cache directory contains intermediate artifacts
ls .metal0/cache/
```

## Architecture Overview

metal0 is an ahead-of-time compiler that translates Python source to Zig, then compiles to native code.

```
Python source → Lexer → Parser → AST → Analysis → Codegen → Zig source → Native binary
```

### Directory Structure

```
src/
├── lexer/              # Python tokenization (lexer.zig)
├── parser/             # AST generation from tokens
├── ast/                # AST node definitions
├── analysis/           # Type inference, semantic analysis, lifetime tracking
│   └── native_types/   # Type system for native codegen
├── codegen/
│   └── native/         # Python AST → Zig code generation (the big one)
│       ├── expressions/    # Expression codegen (binops, calls, etc.)
│       ├── statements/     # Statement codegen (if, for, try, etc.)
│       ├── builtins/       # Built-in function implementations
│       └── main/           # Codegen entry point and state
├── bytecode/           # (Experimental) Bytecode compiler/VM for WASM target
├── main/               # CLI entry point, compiler orchestration
└── compiler.zig        # Top-level compilation pipeline

packages/
└── runtime/            # Zig runtime library
    └── src/
        ├── runtime.zig     # Main runtime exports
        ├── runtime/        # Core runtime (builtins, exceptions, types)
        ├── Objects/        # Python object implementations
        ├── Python/         # Python-specific utilities (formatter, etc.)
        └── Lib/            # Standard library implementations (unittest, etc.)

tests/
├── unit/               # Unit tests (fast, isolated)
├── integration/        # Integration tests
└── cpython/            # CPython compatibility tests (test_*.py from CPython)
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `src/codegen/native/` | The heart of the compiler - translates Python AST to Zig |
| `src/analysis/` | Type inference and semantic analysis |
| `packages/runtime/` | Runtime library linked into compiled binaries |
| `src/bytecode/` | Experimental bytecode VM (for WASM, not primary target) |

### Compilation Flow

1. **Lexer** (`src/lexer/`) - Tokenizes Python source
2. **Parser** (`src/parser/`) - Builds AST from tokens
3. **Analysis** (`src/analysis/`) - Type inference, scope analysis
4. **Codegen** (`src/codegen/native/`) - Generates Zig source code
5. **Zig compiler** - Compiles generated Zig to native binary

## Submitting Changes

1. **Open an issue first** for non-trivial changes
2. **Fork and branch** - Create a feature branch from `main`
3. **Keep PRs focused** - One logical change per PR
4. **Test your changes** - Run `make test-unit` at minimum
5. **Describe what and why** - Not just what you changed, but why

### Commit Messages

We use conventional commits loosely:

```
fix(codegen): Handle edge case in try/except generation
feat(runtime): Add str.partition method
docs: Update installation instructions
test: Add regression test for issue #123
```

### Code Style

- Follow existing patterns in the codebase
- Zig code is auto-formatted on commit (via pre-commit hook)
- Keep functions focused and reasonably sized
- Comments for non-obvious logic

## Getting Help

- **Issues** - For bugs and feature requests
- **Discussions** - For questions and ideas (if enabled)
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (Apache 2.0).

---

Don't worry about getting everything perfect. We'd rather have your contribution than not. Open a draft PR if you're unsure!
