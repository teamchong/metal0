# metal0 Compiler Architecture

This document explains the internal architecture of the metal0 compiler, which compiles Python source code to native binaries via Zig.

## High-Level Pipeline

```
┌─────────────┐    ┌────────┐    ┌────────┐    ┌──────────────┐    ┌─────────┐    ┌────────────┐
│ Python      │ -> │ Lexer  │ -> │ Parser │ -> │ Type         │ -> │ Zig     │ -> │ Zig        │
│ Source      │    │        │    │        │    │ Inference    │    │ Codegen │    │ Compiler   │
└─────────────┘    └────────┘    └────────┘    └──────────────┘    └─────────┘    └────────────┘
     .py              Tokens       AST           NativeTypes        .zig           Binary
```

## Directory Structure

```
metal0/
├── src/
│   ├── main/           # CLI entry point and command handling
│   ├── lexer/          # Tokenization
│   ├── parser/         # AST construction
│   ├── ast/            # AST node definitions
│   ├── analysis/       # Type inference and semantic analysis
│   ├── codegen/
│   │   └── native/     # Zig code generation
│   └── compiler.zig    # Zig compilation orchestration
├── packages/
│   └── runtime/        # Runtime library linked into compiled binaries
└── tests/              # Test suite
```

## Pipeline Stages

### 1. Lexer (`src/lexer/`)

The lexer converts Python source code into a stream of tokens.

**Key files:**
- `tokenizer.zig` - Main tokenizer implementation
- `tokenizer/fstring.zig` - F-string tokenization (handles `f"Hello {name}"`)

**Input:** Raw Python source code (`[]const u8`)
**Output:** Token stream

```python
# Input
x = 42 + 3

# Output tokens
NAME("x"), EQUAL, NUMBER(42), PLUS, NUMBER(3), NEWLINE
```

**Challenges:**
- Python's significant whitespace (INDENT/DEDENT tokens)
- F-string parsing with nested expressions
- String prefix handling (`r""`, `b""`, `f""`)

### 2. Parser (`src/parser/`)

The parser consumes tokens and builds an Abstract Syntax Tree (AST).

**Key files:**
- `parser.zig` - Main parser entry point
- `statements.zig` - Statement parsing (if, for, while, def, class, etc.)
- `postfix/` - Expression parsing with operator precedence

**Input:** Token stream
**Output:** AST (`ast.Node`)

```python
# Input
def greet(name):
    return f"Hello, {name}!"

# Output AST (simplified)
FunctionDef {
    name: "greet",
    args: [Arg { name: "name" }],
    body: [
        Return {
            value: JoinedStr {
                values: [
                    Constant("Hello, "),
                    FormattedValue(Name("name")),
                    Constant("!")
                ]
            }
        }
    ]
}
```

**Challenges:**
- Operator precedence (handled via Pratt parsing)
- Python's complex assignment targets (tuple unpacking, augmented assignment)
- Decorator handling

### 3. AST (`src/ast/`)

Defines all AST node types that represent Python constructs.

**Key files:**
- `ast.zig` - Node type definitions
- `deinit.zig` - Memory cleanup for AST nodes

**Major node categories:**
- **Statements:** `function_def`, `class_def`, `if_stmt`, `for_stmt`, `try_stmt`, `assign`, etc.
- **Expressions:** `call`, `attribute`, `subscript`, `bin_op`, `compare`, `lambda`, etc.
- **Literals:** `constant` (int, float, string, bool, None)

### 4. Type Inference (`src/analysis/`)

Analyzes the AST to infer types for variables and expressions. This enables generating efficient, statically-typed Zig code.

**Key files:**
- `native_types/core.zig` - Type inference engine
- `native_types/calls/` - Return type inference for function calls
- `lifetime.zig` - Variable lifetime analysis
- `traits/` - Type trait definitions (is_numeric, is_iterable, etc.)

**Input:** AST
**Output:** Type information mapped to AST nodes

```python
# Input
x = [1, 2, 3]
y = x[0] + 10

# Inferred types
x: list[int]  -> Zig: std.ArrayList(i64)
y: int        -> Zig: i64
```

**Key type mappings:**
| Python Type | Zig Type |
|-------------|----------|
| `int` | `i64` |
| `float` | `f64` |
| `bool` | `bool` |
| `str` | `[]const u8` |
| `list[T]` | `std.ArrayList(T)` |
| `dict[K,V]` | `std.StringHashMap(V)` or custom |
| `None` | `null` or `?T` |

### 5. Code Generation (`src/codegen/native/`)

The largest and most complex stage. Transforms the typed AST into Zig source code.

**Key files:**
- `main/core.zig` - Main codegen state and entry point
- `expressions.zig` - Expression code generation
- `statements/` - Statement code generation
  - `assign.zig` - Assignment handling
  - `control.zig` - if/while/for loops
  - `try_except.zig` - Exception handling
  - `functions/` - Function and class generation
- `builtins.zig` - Python builtin function implementations
- `builtins_mod.zig` - Builtin module dispatch

#### Exception Handling (`try_except.zig`)

Python's exception handling is translated to Zig's error handling:

```python
# Python
try:
    risky_operation()
except ValueError as e:
    handle_error(e)
```

```zig
// Generated Zig
{
    var e: []const u8 = undefined;
    const __TryHelper_0 = struct {
        fn run(p_e_0: *[]const u8) !void {
            try risky_operation();
        }
    };
    __TryHelper_0.run(&e) catch |err| {
        if (err == error.ValueError) {
            p_e_0.* = runtime.getExceptionStr();
            handle_error(e);
        } else return err;
    };
}
```

**Key challenges:**
- Variable scoping (Python variables escape try blocks)
- Nested try blocks with unique parameter names
- Exception chaining (`raise X from Y`)

#### Class Generation (`statements/functions/generators.zig`)

Python classes become Zig structs with methods:

```python
# Python
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def distance(self):
        return (self.x**2 + self.y**2)**0.5
```

```zig
// Generated Zig
const Point = struct {
    x: i64,
    y: i64,

    pub fn init(allocator: std.mem.Allocator, x: i64, y: i64) @This() {
        return @This(){ .x = x, .y = y };
    }

    pub fn distance(self: *const @This()) f64 {
        return std.math.pow(f64,
            @as(f64, self.x * self.x + self.y * self.y), 0.5);
    }
};
```

**Key challenges:**
- Inheritance (copying parent methods)
- `__new__` vs `__init__` semantics
- Nested classes with variable capture
- Method resolution order

### 6. Runtime Library (`packages/runtime/`)

A Zig library that provides Python-compatible runtime functions.

**Key files:**
- `runtime.zig` - Main exports
- `runtime/builtins.zig` - Builtin functions (len, range, etc.)
- `runtime/exceptions.zig` - Exception types
- `Lib/` - Standard library implementations (unittest, etc.)
- `Python/` - Python type implementations (PyStr, PyList, etc.)

**Provides:**
- Exception types and error handling
- String operations (Python semantics)
- Collection operations
- Type conversions
- Print and formatting

### 7. Zig Compilation (`src/compiler.zig`)

Invokes the Zig compiler to compile generated code to a native binary.

**Process:**
1. Write generated Zig code to `.metal0/cache/`
2. Copy runtime library to cache
3. Invoke `zig build-exe` with appropriate flags
4. Link runtime library
5. Output final binary

## Data Flow Example

Here's how `print(sum([1, 2, 3]))` flows through the compiler:

```
1. LEXER
   "print(sum([1, 2, 3]))"
   -> [NAME("print"), LPAREN, NAME("sum"), LPAREN, LBRACKET,
       NUMBER(1), COMMA, NUMBER(2), COMMA, NUMBER(3),
       RBRACKET, RPAREN, RPAREN]

2. PARSER
   -> Call {
        func: Name("print"),
        args: [
          Call {
            func: Name("sum"),
            args: [
              List { elts: [Constant(1), Constant(2), Constant(3)] }
            ]
          }
        ]
      }

3. TYPE INFERENCE
   -> List type: list[int]
   -> sum() returns: int
   -> print() returns: void

4. CODEGEN
   -> runtime.print("{d}", .{runtime.sum(&[_]i64{1, 2, 3})});

5. ZIG COMPILE
   -> Native binary
```

## Two-Tier Compilation: AOT + Surgical VM Fallback

metal0 uses a **two-tier compilation strategy** to achieve both maximum performance and full Python compatibility:

1. **Tier 1: AOT Compilation** - Static Python code compiles to native Zig (30x faster than CPython)
2. **Tier 2: Bytecode VM** - Dynamic features (`eval()`, `exec()`) use an embedded bytecode interpreter

### Key Principle: Surgical Fallback

**Only the specific expression** falls back to the VM, NOT the entire function or file.

```python
def calculate(x, y):
    a = x + y          # ← AOT compiled to native Zig
    b = a * 2          # ← AOT compiled to native Zig
    c = eval("a + b")  # ← Only this expression uses VM
    return c + 1       # ← AOT compiled to native Zig
```

Generated Zig code:

```zig
fn calculate(x: i64, y: i64) i64 {
    const a = x + y;                          // Native Zig
    const b = a * 2;                          // Native Zig
    const c = runtime.PyValue.from(           // VM call wrapped in PyValue
        try runtime.eval(__global_allocator, "a + b")
    );
    return c.asInt() + 1;                     // Native Zig
}
```

### Three Levels of VM Fallback

| Pattern | Compilation | When Used |
|---------|-------------|-----------|
| **Comptime eval** | Bytecode embedded at compile time | `eval("1 + 2")` - string literal |
| **Runtime eval** | Bytecode compiled at runtime | `eval(user_input)` - dynamic string |
| **Type dunder fallback** | String interpolation to VM | `complex.__eq__(a, b)` - unsupported type dunders |

### Comptime Eval Optimization

When `eval()` has a **string literal** argument, metal0 compiles the bytecode at Zig compile time and embeds it directly:

```python
result = eval("1 + 2 * 3")  # String literal - comptime optimized
```

Generated:

```zig
const _bytecode_0 = [_]u8{ 0x01, 0x02, ... };  // Bytecode embedded at compile time
var _program_0 = runtime.BytecodeProgram.deserialize(__global_allocator, &_bytecode_0);
var _vm_0 = runtime.BytecodeVM.init(__global_allocator);
const result = runtime.PyValue.from(_vm_0.execute(&_program_0));
```

### VM Fallback Analysis (`vm_fallback_analysis.zig`)

Before code generation, metal0 scans function bodies to identify:

1. **Variables used in VM expressions** - Must be available when VM runs
2. **Lambda captures** - Variables captured from outer scope in lambdas
3. **Type dunder patterns** - Calls like `complex.__eq__(a, b)` that need VM

This ensures variables are properly scoped and not optimized away before the VM needs them.

### Performance Impact

| Code Pattern | Execution Path | Relative Speed |
|--------------|----------------|----------------|
| `x + y` (numeric) | Native Zig | 30x CPython |
| `eval("x + y")` literal | Embedded bytecode | ~1x CPython |
| `eval(dynamic_string)` | Runtime bytecode | ~0.8x CPython |
| `complex.__eq__(a, b)` | VM fallback | ~1x CPython |

The key insight: **Contamination is minimal**. One `eval()` doesn't slow down the entire program - only that specific expression pays the VM overhead.

### Source Files

| File | Purpose |
|------|---------|
| `src/codegen/native/builtins/eval.zig` | `eval()` and `exec()` code generation |
| `src/codegen/native/builtins/compile.zig` | `compile()` builtin |
| `src/codegen/native/statements/functions/generators/body/vm_fallback_analysis.zig` | Pre-scan for VM variable usage |
| `packages/runtime/src/bytecode/vm.zig` | Bytecode interpreter |
| `packages/runtime/src/bytecode/frame.zig` | VM stack frame and PyValue |
| `src/codegen/bytecode.zig` | Python-to-bytecode compiler |

## CPython-Compatible Memory Layout

metal0 implements Python types using Zig's `extern struct` with **exact CPython memory layout**. This enables:

1. **C extension compatibility** - C extensions can work with metal0 objects
2. **FFI interop** - Direct memory layout matching CPython
3. **Debugging** - GDB/LLDB can inspect objects using CPython struct definitions

### Example: PyObject Layout

```zig
// packages/runtime/src/cpython.zig

/// PyObject - Base object header (CPython compatible)
/// Layout: ob_refcnt (8 bytes) + ob_type (8 bytes) = 16 bytes
pub const PyObject = extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: *PyTypeObject,
};

/// PyListObject - Exact CPython list layout
pub const PyListObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject,  // Array of PyObject pointers
    allocated: Py_ssize_t,
};

/// PyUnicodeObject - Python string
pub const PyUnicodeObject = extern struct {
    ob_base: PyObject,
    length: Py_ssize_t,
    hash: Py_ssize_t,
    state: u32,
    _padding: u32,
    data: [*]const u8,
};
```

### Type Mapping

| CPython Type | metal0 Zig Type | Memory Compatible |
|--------------|-----------------|-------------------|
| `PyObject*` | `*cpython.PyObject` | ✅ Yes |
| `PyListObject*` | `*cpython.PyListObject` | ✅ Yes |
| `PyLongObject*` | `*cpython.PyLongObject` | ✅ Yes |
| `PyFloatObject*` | `*cpython.PyFloatObject` | ✅ Yes |
| `PyUnicodeObject*` | `*cpython.PyUnicodeObject` | ✅ Yes |
| `PyTypeObject*` | `*cpython.PyTypeObject` | ✅ Yes |

## Shared Infrastructure

Both the AOT compiler and bytecode VM share the same core implementations:

| Component | Location | Used By |
|-----------|----------|---------|
| `cpython.zig` types | `packages/runtime/src/cpython.zig` | AOT + VM |
| `PyValue` (unified) | `packages/runtime/src/Objects/object.zig` | AOT + VM |
| Arithmetic ops | `PyValue.add/sub/mul/div/floordiv/mod/pow` | AOT + VM |
| String operations | `packages/runtime/src/runtime/string_utils.zig` | AOT + VM |
| Integer overflow | `packages/runtime/src/runtime/unified_int_ops.zig` | AOT + VM |

### Design Principles

From `bytecode.zig` header:
```
/// 1. Stable bytecode format (NOT CPython opcodes)
/// 2. VM dispatches to existing runtime functions (no reimplementation)
/// 3. Shares freeze infrastructure with edgebox
```

### How It Works

1. **Unified PyValue**: The `PyValue` type in `Objects/object.zig` is the single source of truth. The VM imports this directly via `bytecode/frame.zig`.

2. **Shared Arithmetic**: Both paths use `PyValue.add()`, `PyValue.sub()`, etc. The VM's `vmAdd/vmSub/vmMul` methods are thin wrappers that call these shared implementations.

3. **Identical Results**: Both paths produce identical results for the same operations because they share the same code.

## Debugging

metal0 supports standard Python toolchains for debugging (e.g., VSCode debugger).
