# Metal0 - Python-to-Zig AOT Compiler

## Core Principles

1. **Transparent by Default** - Folder structure IS the documentation. Agents know what to use by looking at folder names.
2. **Lazy by Default, Zero Copy** - Avoid allocations. Use slices, views, iterators. Never copy when you can borrow.
3. **One Function Per File** - For traits, each function is its own file with header comment explaining when to use.

---

## Agent Rules
1. If changes not made by you, none of your business - don't revert it
2. If build broken by other agents, sleep 30s for other agent to fix the build
3. Never force commit any gitignored files or the .claude folder
4. Never kill other agent running process
5. **NEVER re-implement existing utilities** - check folder structure below first!
6. **Use `./zig-out/bin/metal0 test` for running CPython tests** - zero config, fast by default
7. **READ ERROR MESSAGES** - Don't skip errors. FileNotFound = wrong path. Read the error, fix the cause.
8. **DCE-friendly imports** - New modules must use `runtime.Lib.xxx` or `c_interop.modules.xxx` namespaces (not direct `runtime.xxx`) to enable dead code elimination.
9. **NEVER skip complex tests** - When a test fails, FIX IT. Don't look for "simpler" tests. Complex features are required. Skipping is not acceptable.
10. **Use batch test runner** - Run tests with `./zig-out/bin/metal0 test tests/cpython <pattern>`. The batch runner shares module analysis for faster compilation.
11. **NEVER modify/rename/delete tests/cpython/*.py files** - These are the 390 CPython test files. They are READ-ONLY. If a test takes too long, fix the compiler - don't skip the test.
12. **NEVER poll background tasks** - When running background commands, NEVER check output repeatedly. Let it complete, then check once. Polling burns tokens.
13. **Use @group syntax for platform tests** - Use `@core`, `@linux`, `@macos`, `@windows` to run platform-specific test groups. See "Test Runner" section below.

---

## Finding Files (Quick Reference for Agents)

**Where to find files based on what you're looking for:**

| Looking for... | Location | Example |
|----------------|----------|---------|
| Python source tests | `tests/cpython/test_*.py` | `tests/cpython/test_bool.py` |
| Generated Zig code | `.metal0/gen/<path>/*.zig` | `.metal0/gen/tests/cpython/test_bool.zig` |
| Compiled test binaries | `.metal0/gen/<path>/<name>` | `.metal0/gen/tests/cpython/test_bool` |
| Runtime library (global) | `~/.metal0/runtime/libruntime-latest.a` | Shared across all projects |
| Compiler source | `src/` | `src/codegen/`, `src/analysis/` |
| Runtime source | `packages/runtime/src/` | `packages/runtime/src/runtime.zig` |
| Stdlib modules | `packages/runtime/src/Lib/` | `packages/runtime/src/Lib/os.zig` |

**Path mapping (Python → Generated Zig → Binary):**
```
tests/cpython/test_bool.py           # Source Python
    ↓ codegen
.metal0/gen/tests/cpython/test_bool.zig   # Generated Zig
    ↓ compile
.metal0/gen/tests/cpython/test_bool       # Compiled binary
```

**Project root detection:** metal0 finds project root by looking for (in order):
1. `pyproject.toml` (highest priority)
2. `setup.py` or `setup.cfg`
3. `.git/` directory (fallback)

All `.metal0/` output goes under the detected project root.

---

## Test Runner (Zero Config)

**Fast by default. Fail fast. No flags needed.**

```bash
# Run specific tests by pattern
./zig-out/bin/metal0 test tests/cpython bool float int

# Use @group syntax for platform-specific tests
./zig-out/bin/metal0 test tests/cpython @core      # 286 platform-independent tests
./zig-out/bin/metal0 test tests/cpython @linux     # 18 Linux-specific tests (epoll, ioctl, etc.)
./zig-out/bin/metal0 test tests/cpython @macos     # 33 macOS-specific tests (kqueue, osx_env, etc.)
./zig-out/bin/metal0 test tests/cpython @windows   # 93 Windows-specific tests (winreg, msvcrt, etc.)

# Combine groups and patterns
./zig-out/bin/metal0 test tests/cpython @core @linux   # Core + Linux tests
./zig-out/bin/metal0 test tests/cpython @core bool     # Core group + specific test
```

**Group files:** `.claude/test_groups/{core,linux,macos,windows}.txt`

**Performance:**
- Single test: ~0.16s (batch compile + run)
- Uses batch compilation by default (~9x faster than individual)
- 5s timeout per test - fail fast

**How it works:**
| Phase | What | Caching |
|-------|------|---------|
| Phase 1 | Python → Zig codegen | Skip if `.zig` newer than `.py` AND compiler |
| Phase 2 | Zig → binary (batch) | Skip if binary newer than `.zig`, compiler, AND runtime |
| Phase 3 | Run binaries | Always runs |

**Cache location:**
- Project: `<project>/.metal0/` (auto-created, gitignored)
- Global: `~/.metal0/` (shared runtime across projects)

**Cache invalidation:** Binaries are recompiled when:
- Source `.py` file changes
- Generated `.zig` file changes
- Compiler (`metal0`) is rebuilt
- Runtime library (`libruntime.a`) is rebuilt

---

## CPython Test Categories (CI Setup)

**390 total tests** - NOT all can run on every platform. Categorized by dependencies:

### Test Group CLI Syntax

```bash
# Platform-specific test groups (use @group syntax)
./zig-out/bin/metal0 test tests/cpython @core      # 286 platform-independent tests
./zig-out/bin/metal0 test tests/cpython @linux     # 18 Linux-specific tests
./zig-out/bin/metal0 test tests/cpython @macos     # 33 macOS-specific tests
./zig-out/bin/metal0 test tests/cpython @windows   # 93 Windows-specific tests

# Combine groups
./zig-out/bin/metal0 test tests/cpython @core @linux   # Core + Linux
./zig-out/bin/metal0 test tests/cpython @core bool     # Core + specific test

# Quick validation (known working tests)
./zig-out/bin/metal0 test tests/cpython bool longexp int_literal unary binop float
```

Group files stored in: `.claude/test_groups/{core,linux,macos,windows}.txt`

### Test Scaling Performance
| Tests | Time | Notes |
|-------|------|-------|
| 1 | ~13s | Initial runtime build overhead |
| 5 | ~17s | +0.8s per test |
| 10 | ~20s | +0.3s per test (amortized) |
| 390 | ~2-3min | If all compile successfully |

**Why full suite hangs:** Some tests have infinite loops, network timeouts, or platform-specific hangs. Use patterns to filter:
```bash
# Skip known problematic tests
./zig-out/bin/metal0 test tests/cpython --exclude=asyncio,multiprocessing,subprocess,signal
```

### Problematic Test Categories (investigate further)
- `test_asyncio*` - requires event loop
- `test_multiprocessing*` - requires fork/spawn
- `test_subprocess*` - requires process spawning
- `test_signal*` - requires signal handling
- `test_socket*` - requires network
- `test_ssl*` - requires OpenSSL
- `test_threading*` - may hang on thread issues

### GitHub CI Matrix Example
```yaml
jobs:
  test-portable:
    runs-on: ubuntu-latest
    steps:
      - run: ./zig-out/bin/metal0 test tests/cpython bool float int # ... portable list

  test-macos:
    runs-on: macos-latest
    steps:
      - run: ./zig-out/bin/metal0 test tests/cpython osx_support apple kqueue

  test-linux:
    runs-on: ubuntu-latest
    steps:
      - run: ./zig-out/bin/metal0 test tests/cpython epoll poll resource
```

---

## Type Decision Guide (CHECK BEFORE PATCHING)

**STOP!** Before writing inline type checks, use the existing trait:

| Symptom | Trait to Use | Import |
|---------|--------------|--------|
| Type mismatch in `a + b` | `binaryResultType(left, right)` | `@import("analysis.type_traits")` |
| Check if numeric type | `isNumeric(t)`, `isIntegral(t)` | `@import("analysis.type_traits")` |
| Wrong `%` or `//` result | `getModuloSemantics()`, `getFloorDivSemantics()` | `@import("analysis.operator_traits")` |
| String/bytes confusion | `isStringLike()`, `isBytes()` | `@import("analysis.string_traits")` |
| Container element type | `getElementType()`, `getKeyType()` | `@import("analysis.container_traits")` |
| Function needs allocator? | `needsAllocator(func)` | `@import("analysis.function_traits")` |
| Module func return type? | `lookupFunction(mod, func).return_type` | `@import("analysis.module_traits")` |

```zig
// BAD - inline type check (don't do this)
if (left == .int and right == .float) { result = .float; }

// GOOD - use trait
const type_traits = @import("analysis.type_traits");
const result = type_traits.binaryResultType(left, right);
```

---

## Equality Comparison (CENTRALIZED - DO NOT DUPLICATE)

**The ONE source of truth for equality comparison:**

| Location | Function | Use Case |
|----------|----------|----------|
| `packages/runtime/src/runtime/equality.zig` | `pyAnyEql(a, b)` | **Primary** - handles structs, tuples, numerics, slices, NaN, containers |
| `packages/runtime/src/runtime/equality.zig` | `pySliceEql(T, a, b)` | Slice comparison with NaN semantics |
| `packages/runtime/src/runtime/equality.zig` | `pyTupleEql(a, b)` | Tuple/struct field-by-field |
| `packages/runtime/src/runtime/builtins/operators.zig` | `pyEqual(alloc, a, b)` | Allocator-dependent fallback (BigInt, PyValue conversion) |
| `packages/runtime/src/runtime/builtins/operators.zig` | `assertEqualGeneric(a, b, alloc)` | For assertEqual - delegates to pyAnyEql first |

**NEVER duplicate comparison logic.** If you need equality checking:

```zig
// GOOD - use centralized module
const equality = @import("runtime/equality.zig");
if (equality.pyAnyEql(a, b)) { ... }

// BAD - inline comparison logic
if (info_a == .@"struct") {
    inline for (fields) |f| { ... }  // DON'T DO THIS
}
```

**What `pyAnyEql` handles:**
- Same-type: floats (NaN identity), slices, ArrayLists, structs (field-by-field)
- Cross-type: int coercion, float coercion, ArrayList vs array, PyValue

**What requires allocator (`pyEqual`):**
- BigInt comparisons (uses `eqlInt` method)
- PyValue conversion fallback
- Tagged union handling

---

## Two-Flow Type System (MUST READ)

**Problem**: Type inference can be wrong. If wrong → runtime panic.

```python
x = user_func()      # Could return int, str, None...
# Current: const x: i64 = ...  → PANIC if not int
# Desired: const x: PyValue = ... → Safe, handles any type
```

**Solution**: Split into two flows based on **TypeConfidence**:

| Confidence | Generated Type | Performance | Safety |
|------------|----------------|-------------|--------|
| `certain` | Raw Zig (`i64`, `f64`, `[]const u8`) | Native speed | Must be correct |
| `uncertain` | `runtime.PyValue` | ~5x slower | Always safe |

### Confidence Rules

| Source | Confidence | Example |
|--------|------------|---------|
| Literals | `certain` | `x = 42`, `y = "hello"` |
| Type annotations | `certain` | `x: int = foo()` |
| Known builtins | `certain` | `len(s)`, `range(10)` |
| Arithmetic on certain | `certain` | `x + y` where both certain |
| User functions (no annotation) | `uncertain` | `x = my_func()` |
| Dict/list subscript | `uncertain` | `x = data[key]` |
| Reassignment to different type | `uncertain` | `x = 1; x = "hello"` |

### Key APIs

**Type Inference** (`src/analysis/native_types/`):
```zig
// Check confidence in inferrer
const typed = ti.getTypedVar(name);  // Returns TypedValue with confidence
if (ti.isUncertain(name)) { ... }    // Quick check
if (ti.isCertain(name)) { ... }      // Quick check

// For call inference
const result = calls.inferCallTyped(alloc, var_types, class_fields, func_return_types, call, ti);
if (result.usePyValue()) { ... }     // Use PyValue for uncertain
```

**Codegen** (`src/codegen/native/main/core.zig`):
```zig
// In codegen, check before emitting
if (self.shouldUsePyValue(var_name)) {
    // Emit: const x: runtime.PyValue = runtime.PyValue.from(...);
} else {
    // Emit: const x: i64 = ...; (or let Zig infer)
}
```

**PyValue Operations** (`packages/runtime/src/Objects/object.zig`):
```zig
// Safe arithmetic for uncertain types
const z = x.add(y);      // PyValue + PyValue → PyValue
const z = x.sub(y);      // Subtraction
const z = x.mul(y);      // Multiplication
const z = x.div(y);      // True division (/)
const z = x.floordiv(y); // Floor division (//)
const z = x.mod(y);      // Modulo (%)
const neg = x.neg();     // Negation

// Safe comparison
if (x.eql(y)) { ... }    // Equality
if (x.lt(y)) { ... }     // Less than
if (x.le(y)) { ... }     // Less or equal

// Type extraction (when you need concrete types)
const i = x.toInt();     // ?i64 - safe, returns null if not int
const i = x.asInt();     // i64 - asserts, use when certain
const f = x.toFloat();   // ?f64 - safe extraction
const s = x.toString();  // ?[]const u8 - safe extraction
```

### Key Files

| File | Purpose |
|------|---------|
| `src/analysis/native_types/core.zig` | `TypeConfidence`, `TypedValue` enums |
| `src/analysis/native_types/inferrer.zig` | `var_confidence` maps, `isCertain()`, `isUncertain()` |
| `src/analysis/native_types/calls.zig` | `inferCallTyped()` returns confidence |
| `src/analysis/native_types/calls/static_maps.zig` | `BuiltinFuncMap` - whitelist of builtins with certain return types |
| `src/codegen/native/main/core.zig` | `shouldUsePyValue()`, `isVarUncertain()`, `isVarCertain()` |
| `src/codegen/native/statements/assign/value_generation.zig` | Opens `PyValue.from()` wrapper for uncertain primitives |
| `src/codegen/native/statements/assign.zig` | Closes `PyValue.from()` wrapper (in `pending_shadow_rename` block) |
| `src/codegen/native/expressions/operators/arithmetic.zig` | `PyValueMethods`, `genPyValueBinOp()` for uncertain operands |
| `packages/runtime/src/Objects/object.zig` | `PyValue.add()`, `.sub()`, `.eql()`, `.toInt()`, etc. |

### Key Principle

> **When in doubt, use PyValue**

Better to be 5x slower than CPython than to panic in production.
Certain types still get full native speed.

---

## Integer Overflow Strategy (UnifiedInt)

**Problem**: Python integers have unlimited precision. Type widening causes compilation failures when:
- `1 << 50000` produces BigInt but codegen assumes i64
- `random.randrange(BigInt, BigInt)` tries to use i64 internally

**Solution**: Use `UnifiedInt` - a tagged union that auto-promotes on overflow.

> **Note**: This is orthogonal to Two-Flow Type System. Two-Flow handles type **confidence** (certain/uncertain). UnifiedInt handles integer **size** (i64/BigInt).

| Use Case | Type | Rationale |
|----------|------|-----------|
| Loop counters (`for i in range(n)`) | `i64` | Known small, tight loops |
| Array/slice indices | `i64` | Memory bounded |
| Known-small literals | `i64` | Compile-time known |
| Function params/returns | `UnifiedInt` | Caller may pass BigInt |
| Arithmetic results | `UnifiedInt` | May overflow |
| Crypto/large numbers | `BigInt` | Explicitly large |

```zig
// UnifiedInt auto-promotes on overflow
const UnifiedInt = union(enum) {
    small: i64,      // Fast path
    big: *BigInt,    // Arbitrary precision
};

// Runtime location: packages/runtime/src/Objects/pyint.zig
```

**Key Files:**
- `src/analysis/native_types/core.zig` - `NativeType.unified_int`
- `src/codegen/native/expressions/operators/arithmetic.zig` - `genUnifiedIntBinOp()`
- `packages/runtime/src/Objects/pyint.zig` - `UnifiedInt` implementation

---

## `anytype` Guidelines (PREVENT COMPILE HANGS)

**Problem**: `anytype` causes monomorphization at every call site. 100 calls = 100 copies = compile explosion.

**`anytype` return type = INVALID** - Zig doesn't allow it. Fix immediately if found.

| Context | Use `anytype`? | Alternative |
|---------|---------------|-------------|
| Hot path (builtins, operators) | ❌ NO | `PyValue`, concrete types, or `comptime T: type` |
| One-shot helpers (assertions) | ✅ OK | Low call count, minimal impact |
| Iterator/callback generic | ⚠️ CAREFUL | Use `comptime T: type` with trait bounds |
| Return type | ❌ NEVER | Invalid Zig syntax |

**Refactoring patterns:**

```zig
// BAD - anytype in hot path (called 1000x = 1000 copies)
pub fn add(a: anytype, b: anytype) @TypeOf(a) { return a + b; }

// GOOD - PyValue for runtime polymorphism (one copy)
pub fn add(a: PyValue, b: PyValue) PyValue {
    return switch (a) {
        .int => |ai| switch (b) { .int => |bi| .{ .int = ai + bi }, ... },
        ...
    };
}

// GOOD - comptime T for compile-time known types (bounded copies)
pub fn add(comptime T: type, a: T, b: T) T { return a + b; }

// GOOD - overloads for common types (3 copies max)
pub fn addInt(a: i64, b: i64) i64 { return a + b; }
pub fn addFloat(a: f64, b: f64) f64 { return a + b; }
```

**Audit command**: `grep -rn ": anytype" packages/runtime/src/ | wc -l`

**Current status** (723 uses):
- `builtins.zig` (75) - HIGH PRIORITY to refactor
- `operator.zig` (37) - HIGH PRIORITY to refactor
- `assertions_*.zig` (45) - OK (one-shot)

---

## Dunder Method Dispatch Pattern (MUST READ)

**Type constructors** (`bool()`, `int()`, `float()`, `str()`) must check for dunder methods on class instances at **codegen time** using `ClassTraits`.

**Python Protocol:**
| Constructor | Primary Method | Fallback |
|-------------|----------------|----------|
| `bool(x)` | `x.__bool__()` | `x.__len__() != 0` |
| `int(x)` | `x.__int__()` | `x.__index__()` |
| `float(x)` | `x.__float__()` | - |
| `str(x)` | `x.__str__()` | `x.__repr__()` |

**Codegen Pattern** (add to `genBool`, `genInt`, `genFloat`, `genStr`):
```zig
// Check if class instance has dunder method
const DunderInfo = struct { has_primary: bool, has_fallback: bool };
const dunder_info: DunderInfo = blk: {
    if (args[0] == .name) {
        const var_name = args[0].name.id;
        if (self.getVarType(var_name)) |var_type| {
            if (type_traits.isClassInstance(var_type)) {
                const class_name = var_type.class_instance;
                break :blk .{
                    .has_primary = self.classHasMethod(class_name, "__bool__"),
                    .has_fallback = self.classHasMethod(class_name, "__len__"),
                };
            }
        }
    }
    break :blk .{ .has_primary = false, .has_fallback = false };
};

// Generate direct method call (compile-time dispatch, no runtime overhead)
if (dunder_info.has_primary and args[0] == .name) {
    if (self.inside_try_body) {
        try self.emit("(try ");
        try self.genExpr(args[0]);
        try self.emit(".__bool__())");
    } else {
        try self.emit("(");
        try self.genExpr(args[0]);
        try self.emit(".__bool__() catch false)");
    }
    return;
}
```

**Key Files:**
- `src/codegen/native/builtins/conversions/int_conv.zig` - `genBool`, `genInt`
- `src/codegen/native/builtins/conversions/float_conv.zig` - `genFloat` (reference implementation)
- `src/codegen/native/builtins/conversions/str_conv.zig` - `genStr`
- `packages/runtime/src/runtime/type_builtins.zig` - Runtime fallback (`boolBuiltinCall`, etc.)

**Runtime Fallback** (for unknown types, `assertRaises`, etc.):
```zig
// Uses @hasDecl for runtime dispatch
if (@hasDecl(ChildType, "__bool__")) {
    return value.__bool__();
}
```

---

## Type Inference Scoping (MUST READ)

**Block-scoped variables** (comprehensions, for loops) must use `putTempVar`/`restoreTempVar` to avoid polluting global `var_types`:
```zig
const old = ti.putTempVar(var_name, .{ .int = .bounded }) catch null;
// ... infer with temp var visible ...
ti.restoreTempVar(var_name, old);
```

---

## Zig 0.15 API Changes (MUST READ)

**ArrayList** - No longer stores allocator, pass to every method:
```zig
// OLD (0.14)                          // NEW (0.15)
var list = ArrayList(T).init(alloc);   var list: ArrayList(T) = .{};
list.append(item);                     list.append(alloc, item);
list.deinit();                         list.deinit(alloc);
```

**Reader/Writer** - Now concrete types with explicit buffers:
```zig
// OLD: var bw = std.io.bufferedWriter(file); const w = bw.writer();
// NEW: var buf: [4096]u8 = undefined; var w = file.writer(&buf);
```

**Process termination** - Now tagged union:
```zig
// OLD: if (result.term.Exited != 0)
// NEW: switch (result.term) { .exited => |code| if (code != 0) ... }
```

**Removed:** `async/await`, `usingnamespace`, `BoundedArray`, `LinearFifo`

---

## Codegen Performance Checklist (PREVENT COMPTIME EXPLOSION)

**Problem**: Zig comptime is O(n²) - inline blocks get monomorphized per call site. 100 slice operations = 100 copies of inline logic = compilation timeout.

**Symptoms of comptime explosion:**
- Compilation >30s for simple files
- `inline for` inside loops
- `@hasField` / `@TypeOf` checks repeated many times
- Generated blocks >500 chars with type introspection

**Before emitting inline code, ask:**

| Question | If Yes → Action |
|----------|-----------------|
| Is this >50 lines? | Extract to `packages/runtime/src/runtime/` |
| Does it use `inline for` or `@TypeOf`? | Extract to runtime helper |
| Will this be called in loops? | Extract to runtime helper |
| Can I monomorphize on 1-2 type params? | Use generic runtime function |

**Runtime helpers location** (`packages/runtime/src/runtime/`):
- `string_utils.zig` - string operations (pyJoin, toUpper)
- `int_ops.zig` - integer operations (toInt, divideInt)
- `float_ops.zig` - float operations (pyFloatMod)
- `slice_ops.zig` - slice operations (sliceWithStep)
- `builtins.zig` - built-in functions (len, range, print)

**Wrapper types for interface compatibility:**
```zig
// If existing codegen expects .items for iteration:
pub fn SliceResult(comptime T: type) type {
    return struct { items: []T };
}
// Check downstream usage before changing return types!
```

**Example - BAD vs GOOD:**
```zig
// BAD: 137 lines of inline comptime per slice (O(n²))
inline for (std.meta.fields(@TypeOf(__s)), 0..) |f, i| { ... }

// GOOD: Single function call, compiled once (O(n))
runtime.slice_ops.sliceWithStep(T, allocator, items, start, end, step)
```

---

## metal0 CLI Reference

**Always use `./zig-out/bin/metal0` (not just `metal0`) to ensure using the locally built version.**

### Basic Usage (python3-compatible)
```bash
metal0 <file.py>              # Compile and run (30x faster than CPython)
metal0 -c "print('hi')"       # Execute code string
metal0 -m module              # Run module as script
metal0 -                      # Read from stdin
```

### Package Commands (pip-compatible)
```bash
metal0 install requests       # Install from PyPI
metal0 uninstall requests     # Remove package
metal0 freeze                 # Output installed packages
metal0 list                   # List installed packages
metal0 show requests          # Show package info
metal0 cache purge            # Clear cache
```

### Build Commands
```bash
metal0 build app.py                    # Compile to native binary
metal0 build app.py -o myapp           # Custom output name
metal0 build --target wasm-edge app.py # Cross-compile to WASM
metal0 run app.py                      # Compile and run
metal0 test tests/                     # Run test suite (TODO: add --filter)
```

### Build Options
| Flag | Description |
|------|-------------|
| `--target <t>` | Cross-compile: native, wasm-browser, wasm-edge, linux-x64, linux-arm64, macos-x64, macos-arm64, windows-x64 |
| `--debug, -g` | Emit debug info (.metal0.dbg.json) |
| `--force` | Recompile even if cached |
| `--binary, -b` | Output standalone binary |

### Test Command (bun-style)
```bash
metal0 test tests/cpython              # Run all tests in directory
metal0 test tests/cpython bool float   # Filter by file pattern (test_bool.py, test_float.py)
metal0 test tests/cpython -t "add"     # Filter by test name
metal0 test --timeout=10               # 10s per-test timeout (default: 5s - fail fast!)
metal0 test --bail=5                   # Stop after 5 failures
metal0 test --jobs=16                  # Parallelism (default: CPU count)
metal0 test --dots                     # Compact output (. = pass, x = fail, ? = timeout)
metal0 test --help                     # Show all options
```

### How Compilation Works
1. **Parse** - Python source → AST
2. **Analyze** - Type inference, call graph, trait analysis
3. **Codegen** - AST → Zig source code
4. **Compile** - Zig → native binary (via zig build-exe)
5. **Run** - Execute binary (if not --binary)

### Output Locations
| What | Where |
|------|-------|
| metal0 binary | `./zig-out/bin/metal0` |
| Generated Zig code | `<project>/.metal0/gen/` |
| Compiled binaries | `<project>/.metal0/gen/<path>/` |
| Global runtime cache | `~/.metal0/runtime/libruntime-latest.a` |

**Two-tier build structure:**
- **Project-local** `<project>/.metal0/` - codegen, binaries (project-specific)
- **Global** `~/.metal0/` - shared runtime library (reused across all projects)

---

## Package Structure

**Folder structure IS the documentation.**
- Use namespaced imports: `@import("utils.hashmap_helper")`
- Module convention: `dirname.zig` + `dirname/` (NOT `dirname/__init__.zig`)

CPython source: `~/Downloads/repos/cpython/`

```
# BUILD & CACHE (gitignored)
zig-out/                      # 🔨 Zig build output (zig build default)
└── bin/metal0                # 🔨 Compiled metal0 binary (ALWAYS use this instead of just metal0)
.zig-cache/                   # 🔨 Zig build cache (zig build default)
.metal0/                      # 🔨 Metal0 project-local cache (at project root)
├── gen/                      # 🔨 Generated code (mirrored source structure)
│   └── tests/cpython/        # 🔨 Example: tests/cpython/*.py → gen/tests/cpython/*.zig
├── lib/                      # 🔨 Linked libraries (project-specific)
└── .zig-cache/               # 🔨 Zig cache for batch compilation

~/.metal0/                    # 🔨 Global cache (shared across ALL projects)
├── runtime/                  # 🔨 Precompiled runtime library
│   └── libruntime-latest.a   # 🔨 Built once, shared everywhere
└── .zig-cache/               # 🔨 Zig cache for runtime builds

# EXTERNAL DEPS (committed to git)
vendor/                       # 📎 Vendored C libraries (source code, not gitignored)
└── libdeflate/               # 📎 Compression library

# CONFIG
build.zig                     # Registers @import("name") → file mappings (see lines 187-200)
Makefile                      # Build/test/benchmark commands (ALWAYS run script, benchmark using this)

# SOURCE CODE
src/
├── utils/                    # ⭐ COMPILER HELPERS → @import("utils.xxx")
│   ├── hashmap_helper.zig    # ⭐ @import("utils.hashmap_helper") - ALWAYS use for string hashmaps
│   ├── allocator_helper.zig  # ⭐ @import("utils.allocator_helper") - c_allocator/GPA selection
│   ├── wyhash.zig            # ⭐ Fast hashing (used by hashmap_helper)
│   ├── fnv_hash.zig          # ⭐ @import("utils.fnv_hash") - FNV-1a hashing
│   └── zig_keywords.zig      # ⭐ @import("utils.zig_keywords") - Escape Zig reserved words
│
├── analysis/
│   └── traits/                     # ⭐ ANALYSIS TRAITS - one function per file
│       ├── type_traits/            # Type checking & inference
│       │   ├── isNumeric.zig       # Check if type supports +,-,*,/ (int/float/bigint/complex)
│       │   ├── isIntegral.zig      # Check if type is int (for bitwise ops, array index)
│       │   ├── isFloating.zig      # Check if type is float (for %, // semantics)
│       │   ├── isIndexable.zig     # Check if obj[key] is valid
│       │   ├── isSliceable.zig     # Check if obj[start:end] is valid
│       │   ├── isContainer.zig     # Check if type has elements (list/dict/set/tuple)
│       │   ├── isSequence.zig      # Check if type is ordered (list/tuple/str/bytes)
│       │   ├── isMapping.zig       # Check if type is key-value (dict)
│       │   ├── isIterable.zig      # Check if "for x in obj" is valid
│       │   ├── isUnknown.zig       # Check if type needs runtime dispatch
│       │   ├── isNone.zig          # Check if type is None
│       │   ├── isBoolean.zig       # Check if type is bool
│       │   ├── isArray.zig         # Check if type is array
│       │   ├── isCallable.zig      # Check if type is callable (function/method)
│       │   ├── isClassInstance.zig # Check if type is class instance
│       │   ├── areComparable.zig   # Check if a == b is valid
│       │   ├── areOrderable.zig    # Check if a < b is valid
│       │   ├── isConvertible.zig   # Check if implicit conversion valid (int->float)
│       │   ├── needsPromotion.zig  # Check if mixed-type arithmetic needs cast
│       │   ├── binaryResultType.zig # Get result type of a + b, a * b, etc
│       │   └── getIndexResultType.zig # Get type of obj[i]
│       │
│       ├── string_traits/          # String/bytes type operations
│       │   ├── isStringLike.zig    # Check if string or bytes (for len, concat)
│       │   ├── isBytes.zig         # Check if bytes (for b'...' repr)
│       │   ├── isString.zig        # Check if string (for .encode())
│       │   ├── canConcat.zig       # Check if str+str or bytes+bytes valid
│       │   ├── canRepeat.zig       # Check if "ab"*3 valid
│       │   ├── getConcatResultType.zig  # Get type of str+str
│       │   ├── getRepeatResultType.zig  # Get type of str*int
│       │   ├── getReprFn.zig       # Get repr function name
│       │   ├── getReprPrefix.zig   # Get repr prefix ("'" or "b'")
│       │   ├── supportsEncode.zig  # Check if .encode() valid
│       │   └── supportsDecode.zig  # Check if .decode() valid
│       │
│       ├── container_traits/       # Container type operations
│       │   ├── isList.zig          # Check if list (for .append())
│       │   ├── isDict.zig          # Check if dict (for .keys())
│       │   ├── isSet.zig           # Check if set (for .add())
│       │   ├── isTuple.zig         # Check if tuple (immutable)
│       │   ├── isMutableContainer.zig   # Check if modifiable
│       │   ├── isImmutableContainer.zig # Check if frozen
│       │   ├── getElementType.zig  # Get element type for list/set
│       │   ├── getKeyType.zig      # Get key type for dict
│       │   ├── getValueType.zig    # Get value type for dict
│       │   ├── supportsPush.zig    # Check if .append() valid
│       │   ├── supportsAdd.zig     # Check if set.add() valid
│       │   ├── supportsSetItem.zig # Check if obj[k]=v valid
│       │   ├── supportsGetItem.zig # Check if obj[k] valid
│       │   ├── supportsConcat.zig  # Check if list+list valid
│       │   ├── supportsRepeat.zig  # Check if list*int valid
│       │   └── getIteratorElementType.zig # Get type when iterating
│       │
│       ├── operator_traits/        # Python vs Zig operator semantics
│       │   ├── getModuloSemantics.zig   # % - floored vs truncated
│       │   ├── getFloorDivSemantics.zig # // - @divFloor vs @floor(a/b)
│       │   ├── getPowerSemantics.zig    # ** - may return complex
│       │   ├── isFloatType.zig     # Check if float/complex
│       │   ├── hasFloatOperand.zig # Check if either operand is float
│       │   ├── hasUnknownOperand.zig # Check if runtime dispatch needed
│       │   ├── needsFloatModulo.zig # Check if pyFloatMod needed
│       │   └── needsFloatFloorDiv.zig # Check if float floor div
│       │
│       ├── function_traits/        # Function analysis (use CallGraph)
│       │   ├── types.zig           # Core types: FunctionTraits, ClassTraits, TypeHint
│       │   ├── call_graph.zig      # CallGraph building from AST, analyzeStatement
│       │   ├── method_dispatch.zig # FloatMethods, IntMethods, DictMethods, ListMethods
│       │   ├── closure_analysis.zig # ClosureReturnType, inferExprReturnType
│       │   ├── mutation_analysis.zig # MutatedVarSet, UsedVarsSet
│       │   ├── simd_analysis.zig   # SimdInfo, ParallelInfo for list comprehensions
│       │   ├── allocator_analysis.zig # analyzeNeedsAllocator, analyzeUsesAllocatorParam
│       │   └── class_analysis.zig  # analyzeClassTraits, BoundMethodRefs
│       │
│       ├── module_traits/          # Cross-module function/constant registry
│       │   ├── analyzeModule.zig   # Analyze AST → ModuleInfo
│       │   ├── lookupFunction.zig  # Get FunctionTraits for module.func
│       │   ├── lookupConstant.zig  # Get ConstantMeta for module.CONST
│       │   └── isLocalModule.zig   # Check if local .py vs stdlib
│       │
│       ├── type_traits.zig         # Re-exports all type_traits/
│       ├── string_traits.zig       # Re-exports all string_traits/
│       ├── container_traits.zig    # Re-exports all container_traits/
│       ├── operator_traits.zig     # Re-exports all operator_traits/
│       ├── function_traits.zig     # Re-exports + CallGraph + full impl
│       └── module_traits.zig       # ModuleInfo, ModuleRegistry, re-exports
│
│   └── native_types/               # ⭐ TYPE INFERENCE SYSTEM (Two-Flow)
│       ├── core.zig                # ⭐ TypeConfidence (certain/uncertain), TypeSource, TypedValue
│       ├── inferrer.zig            # ⭐ TypeInferrer - main type inference engine
│       │                           #   - var_confidence: HashMap tracking confidence per var
│       │                           #   - isCertain(name), isUncertain(name) helpers
│       │                           #   - getTypedVar(name) → TypedValue with confidence
│       │                           #   - putTempVar/restoreTempVar for block scopes
│       │                           #   - enterScope/exitScope for function scopes
│       ├── expressions.zig         # Type inference for expressions
│       ├── statements.zig          # Type inference for statements (tracks call confidence)
│       └── calls.zig               # ⭐ inferCallTyped() - returns TypedValue with confidence
│
├── codegen/native/                 # Zig code generation
│   ├── main/
│   │   └── core.zig                # ⭐ shouldUsePyValue(), isVarUncertain(), isVarCertain()
│   ├── statements/assign/
│   │   ├── value_generation.zig    # ⭐ Opens PyValue.from() wrapper for uncertain primitives
│   │   └── assign.zig              # ⭐ Closes PyValue.from() wrapper (line 1235)
│   └── expressions/operators/
│       └── arithmetic.zig          # ⭐ PyValueMethods, genPyValueBinOp() for uncertain operands
└── parser/                   # Python parser

packages/
├── runtime/src/              # @import("runtime") - registered in build.zig
│   ├── runtime/              # ⭐ RUNTIME HELPERS (use relative: @import("../runtime/xxx.zig"))
│   │   ├── string_utils.zig  # ⭐ pyJoin, toUpper, toLower
│   │   ├── int_ops.zig       # ⭐ toInt, divideInt, moduloInt
│   │   ├── float_ops.zig     # ⭐ pyFloatMod, numToFloat
│   │   ├── exceptions.zig    # ⭐ PythonError, setException
│   │   └── builtins.zig      # ⭐ len, range, print, pow, etc.
│   │
│   ├── Lib/                  # 📦 CPYTHON STDLIB (mostly stubs, some real - run check script)
│   ├── Objects/              # 📦 Runtime object implementations
│   │   └── object.zig        # ⭐ PyValue (Two-Flow) - tagged union for uncertain types
│   │                         #   - add(), sub(), mul(), div(), floordiv(), mod() - arithmetic
│   │                         #   - neg() - unary negation
│   │                         #   - eql(), lt(), le() - comparison
│   │                         #   - from(), fromAlloc() - construct from Zig types
│   ├── Modules/              # 📦 Runtime C extension modules
│   └── Python/               # 📦 CPYTHON Python/ MIRROR (100 files) - FIXED
│
├── c_interop/src/            # 📦 CPYTHON C-API MIRROR - FIXED
│   ├── objects/              # 📦 mirrors cpython/Objects/ (48 files)
│   └── modules/              # 📦 mirrors cpython/Modules/ (101 files)
│
├── shared/                   # ⭐ @import("shared").json, @import("h2")
│   ├── json/                 # ⭐ SIMD JSON (replaces: ujson, orjson, simplejson)
│   └── http/h2/              # ⭐ HTTP/1.1 + HTTP/2 + TLS Client (replaces: requests, httpx, urllib3, aiohttp)
│
├── collections/              # @import("collections") - list, dict, set, tuple
├── regex/                    # @import("regex") - replaces: regex
├── bigint/                   # @import("bigint") - arbitrary precision integers
├── tokenizer/                # @import("tokenizer") - replaces: tiktoken, tokenizers
└── websocket/                # @import("websocket") - replaces: websockets, websocket-client

# TESTS & BENCHMARKS
tests/
├── unit/                     # Unit tests (make test-unit)
├── integration/              # Integration tests (make test-integration)
└── cpython/                  # CPython compatibility tests (make test-cpython)

benchmarks/                   # Performance benchmarks (make benchmark-*)
├── fib/                      #    Fibonacci (vs Rust, Go, Python)
├── json/                     #    JSON parsing
├── http/                     #    HTTP client
└── webserver/                #    Web server throughput (wrk)

# EXAMPLES & DOCS
examples/                     # Example projects (basic, web, wasm, docker)
docs/                         # Documentation (architecture.md)

# SCRIPTS
scripts/gen_packages.py       # Regenerates package imports (make gen-packages)

# CI/CD
.github/workflows/            # GitHub Actions workflows
```

**Legend:** `⭐` = Helper (check before implementing) | `📦 FIXED` = CPython mirror | `🔨` = Build output (gitignored) | `📎` = External deps

---

## Auto-Import System (DO NOT ADD MANUAL IMPORTS)

**Modules are auto-discovered from folder structure - NO manual registration needed!**

The import system recursively scans `packages/runtime/src/Lib/` and auto-generates imports:
- `src/codegen/native/stdlib_modules_gen.zig` - Auto-generated with **1089+ modules**
- Uses `.` notation for submodules: `encodings.koi8_t`, `http.client`, `xml.etree.ElementTree`

**import_registry.zig contains ONLY essential overrides:**
- `func_meta` - Function metadata introspection
- C library wrappers (`_abc`, `_collections`, `_functools`, etc.)
- Special aliases (`builtins`, `sys`, `os`)

**To add a new module:**
1. Create `.zig` file in appropriate `Lib/` subfolder
2. Run `zig build` - module auto-discovered
3. **DO NOT** manually edit import_registry.zig or stdlib_modules_gen.zig

**Two-tier import strategy:**
- Tier 1: `zig_runtime` - Pure Zig implementations (preferred)
- Tier 2: `c_library` - C extension fallback

---

## Package System (Auto-Discovery from Folder Structure)

**Folder structure tells the full story - no hidden logic!**

All packages in `packages/` are auto-discovered via `package.json` manifest.

### Package Convention

```
packages/{name}/
├── package.json      # Required manifest
└── src/main.zig      # OR {name}.zig at root
```

### package.json Schema

```json
{
  "name": "websocket",
  "root": "src/main.zig",
  "pypi": ["websockets", "websocket-client"],
  "deps": ["json", "h2"]
}
```

| Field | Description |
|-------|-------------|
| `name` | Package name for `@import("{name}")` |
| `root` | Entry point file (relative to package dir) |
| `pypi` | PyPI packages this replaces (skips download) |
| `deps` | Dependencies on other packages |

### Auto-Generated Files

Run `python3 scripts/gen_packages.py` to regenerate:

| Generated File | Purpose |
|----------------|---------|
| `packages/pkg/src/native_modules_gen.zig` | PyPI skip list |
| `src/codegen/native/packages_gen.zig` | Package import mappings |

### Adding a New Package

1. Create `packages/{name}/package.json`
2. Create `packages/{name}/src/main.zig`
3. Run `python3 scripts/gen_packages.py`
4. Done - auto-discovered!

### Adding a PyPI Override

To replace a PyPI package with native Zig:

1. Add `"pypi": ["package-name"]` to your package.json
2. Run `python3 scripts/gen_packages.py`
3. Package manager will skip PyPI download, use native impl

(See folder structure above for current overrides - marked with "replaces:")

---

## CPython Mirror

Verify: `~/Downloads/repos/metal0/.claude/check-cpython-mirror.sh`

---

## CPython Test Progress

**Status:** Tests currently have compile/runtime errors after dunder dispatch refactoring.

**Previously passing (need regression fix):**
- `bool` - runtime error (assertRaises semantic issue)
- `longexp` - runtime error (assertEqual failure)
- `int_literal` - compile error
- `unary` - compile error
- `binop` - compile error
- `float` - compile error

**Recent fixes:**
- Added `runtime.builtinLen` export (was missing)
- Fixed `Python/errors/core_api.zig` import path (`../runtime` → `../../runtime`)
- Fixed `len_builtin` for Zig 0.15 (`.Slice` → `.slice`, removed error union)

**To investigate:** Check `.metal0/gen/**/*.zig` for generated code errors after running test.
