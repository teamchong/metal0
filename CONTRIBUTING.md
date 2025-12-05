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

```bash
# Clone and build
git clone https://github.com/paiml/metal0
cd metal0
make install

# Run tests
make test-unit        # Fast unit tests
make test             # Full test suite

# Build after changes
zig build
```

### Prerequisites

- **Zig 0.14.0** - Install from [ziglang.org](https://ziglang.org/download/)
- **macOS or Linux** - Windows support is limited

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

## Testing

```bash
# Run a specific Python file through metal0
./zig-out/bin/metal0 path/to/test.py

# Run CPython compatibility tests
./zig-out/bin/metal0 tests/cpython/test_exceptions.py

# Check generated Zig code (useful for debugging)
cat .metal0/cache/metal0_main_*.zig
```

## Architecture Overview

```
src/
├── lexer/          # Python tokenization
├── parser/         # AST generation
├── analysis/       # Type inference, semantic analysis
├── codegen/native/ # Python AST → Zig code generation
└── main/           # CLI, compiler orchestration

packages/runtime/   # Zig runtime library (Python builtins, types)
tests/cpython/      # CPython compatibility tests
```

## Getting Help

- **Issues** - For bugs and feature requests
- **Discussions** - For questions and ideas (if enabled)
- Check existing issues before creating new ones

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT).

---

Don't worry about getting everything perfect. We'd rather have your contribution than not. Open a draft PR if you're unsure!
