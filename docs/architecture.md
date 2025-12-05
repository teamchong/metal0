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

## Contributing to Specific Areas

### Adding a New Builtin Function

1. Add to `src/codegen/native/builtins_mod.zig` (Funcs map)
2. Implement in `src/codegen/native/builtins.zig` or `builtins/collections.zig`
3. Add runtime support in `packages/runtime/src/runtime/builtins.zig` if needed
4. Add type inference in `src/analysis/native_types/calls/builtin_calls.zig`

### Adding a New String Method

1. Add to `packages/runtime/src/Python/pyStr.zig`
2. Add codegen dispatch in `src/codegen/native/expressions/method_calls/string_methods.zig`
3. Add type inference for return type

### Fixing a Code Generation Bug

1. Create a minimal Python test case
2. Run `metal0 <file.py>` and examine `.metal0/cache/metal0_main_*.zig`
3. Identify the incorrect Zig output
4. Trace back through codegen to find the responsible code
5. Common locations:
   - `expressions.zig` for expression issues
   - `statements/` for statement issues
   - `try_except.zig` for exception handling

### Adding Exception Type Support

1. Add to `src/codegen/native/builtins_mod.zig` (Funcs map with `h.err()`)
2. Add to `src/codegen/native/shared_maps.zig` (RuntimeExceptions)
3. Add to `packages/runtime/src/runtime/exceptions.zig` if needed

## Debugging Tips

- **View generated Zig:** Check `.metal0/cache/metal0_main_*.zig`
- **Zig compilation errors:** The line numbers in errors reference the generated file
- **AST debugging:** Add `std.debug.print` in parser to dump nodes
- **Type inference:** Check `type_inferrer.var_types` contents

## Known Limitations

- No support for `async`/`await`
- Limited metaclass support
- No `__slots__`
- Subset of standard library
- No dynamic code execution (`eval`, `exec`)
