# metal0 Test Suite

Comprehensive tests ensuring Python/metal0 output equivalence.

## Structure

- **`examples/`** - Demo files showing how to use metal0 (keep these!)
- **`tests/`** - Automated tests that verify demos work correctly

## Quick Start

```bash
# Run all tests in parallel (recommended - 5x faster)
pytest

# Run specific test file
pytest tests/test_regression.py -v

# Run single test
pytest tests/test_regression.py::TestExamples::test_example[fibonacci-path3] -v
```

## Test Files

### `test_regression.py` - Regression Tests (28 tests)
Runs all `examples/*.py` files and verifies Python/metal0 output matches.
- Auto-discovers all example files
- Compiles each with metal0
- Compares Python vs metal0 output
- **Status: 28/28 PASSING**
- **Purpose:** Ensure demos stay working (regression testing)

### `test_string_methods.py` - String Method Tests (16 tests)
Parameterized tests for all string methods:
- `upper()`, `lower()`, `strip()`, `split()`, `replace()`
- `startswith()`, `endswith()`, `find()`, `count()`

### `test_list_methods.py` - List Method Tests (19 tests)
Parameterized tests for all list methods:
- `append()`, `pop()`, `extend()`, `remove()`, `reverse()`
- `count()`, `index()`, `insert()`, `clear()`
- List comprehensions

## Performance

- **Serial**: ~96 seconds (3.4s per test)
- **Parallel (`-n auto`)**: ~19 seconds (5x faster)

Slowness is due to Zig compilation. Each test compiles a fresh binary.

## How Tests Work

1. Write Python code to temp file
2. Run with CPython → capture stdout
3. Compile with metal0 compiler → Zig binary
4. Run metal0 binary → capture stderr (uses `std.debug.print`)
5. Assert outputs match exactly

## Test Coverage

- ✅ All 19 built-in methods (strings, lists, dicts)
- ✅ List comprehensions
- ✅ Operators (`in`, slicing)
- ✅ Control flow (if, for, while)
- ✅ Type system integration

**Total: 63 tests, ALL PASSING**
