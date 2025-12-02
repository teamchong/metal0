# metal0

AOT Python compiler. 30x faster than CPython.

**[TODO List](TODO.md)** | **[Agents](AGENTS.md)**

## PRIORITY 1: Function Traits Framework

**USE `src/analysis/function_traits.zig` FOR ALL ANALYSIS DECISIONS!**

Before fixing any codegen issue, check if `function_traits` can solve it:
- Async/await issues → `shouldUseStateMachineAsync()`
- Parameter mutability → `isParamMutated()`
- Error union decisions → `needsErrorUnion()`
- Allocator passing → `needsAllocator()`
- Optimization → `isPure()`, `canUseTCO()`
- Dead code → `isDeadCode()`

**Wire up queries in codegen before adding ad-hoc solutions!**

## Commands

```bash
make help              # All available commands
metal0 file.py --force  # ALWAYS --force after code changes

# After code changes - build & test in ONE command (saves tokens):
zig build && ./zig-out/bin/metal0 file.py --force
```

## Where Things Are

| What | Where |
|------|-------|
| **Compiler** | |
| Lexer | `src/lexer/` |
| Parser | `src/parser/` |
| Type inference | `src/analysis/` |
| Codegen | `src/codegen/native/` (see structure below) |
| Import resolver | `src/import_resolver/` |
| **Packages** | |
| Runtime | `packages/runtime/src/` |
| String methods | `packages/runtime/src/string/` |
| JSON lib | `packages/shared/json/` |
| Regex | `packages/regex/` |
| Tokenizer | `packages/tokenizer/` |
| Collections | `packages/collections/` |
| Async | `packages/async_runtime/` |
| C interop | `packages/c_interop/` |
| **Package Manager** | `packages/pkg/src/` |
| PEP 440 (versions) | `packages/pkg/src/parse/pep440.zig` |
| PEP 508 (deps) | `packages/pkg/src/parse/pep508.zig` |
| requirements.txt | `packages/pkg/src/parse/requirements.zig` |
| METADATA parser | `packages/pkg/src/parse/metadata.zig` |
| RECORD parser | `packages/pkg/src/parse/record.zig` |
| **Other** | |
| Tests | `tests/{unit,integration,cpython}/` |
| Benchmarks | `benchmarks/{fib,dict,string,json,regex,tokenizer}/` |
| Examples | `examples/basic/` |
| Build config | `build.zig` (module definitions) |
| Bun reference | `~/downloads/repos/bun/` |
| CPython reference | `~/downloads/repos/cpython/` |

## Add Feature

| Type | Files |
|------|-------|
| Built-in func | `src/codegen/native/expressions/calls.zig` → `packages/runtime/src/runtime.zig` |
| Stdlib import | `src/codegen/native/{json,re,os,math}.zig` + `src/import_resolver.zig` |
| String method | `packages/runtime/src/string/methods.zig` |
| List/dict method | `packages/runtime/src/runtime.zig` |
| New module | `build.zig` (addModule) → `@import("name")` |
| Type support | `src/analysis/type_inference.zig` |

## Code Patterns

| Pattern | Import | Note |
|---------|--------|------|
| Allocator | `@import("allocator_helper")` | 29x faster than GPA |
| HashMap | `@import("hashmap_helper")` | wyhash |
| JSON | `@import("json")` | NOT std.json |
| Collections | `@import("collections")` | Generic dict/list |
| HTTP Client | `@import("h2")` | `packages/shared/http/h2/h2.zig` - unified HTTP/1.1 & HTTP/2, TLS 1.3 |

## Parser Helpers (`src/parser.zig`)

| Helper | Usage | Note |
|--------|-------|------|
| `allocNode(node)` | `try self.allocNode(value)` | Copy node to heap |
| `allocNodeOpt(node?)` | `try self.allocNodeOpt(maybe)` | Optional variant |
| `parseBinOp(next, mappings)` | `self.parseBinOp(parseNext, &.{...})` | Generic binary operator parser |

```zig
// Binary operator - use comptime mappings
pub fn parseBitOr(self: *Parser) ParseError!ast.Node {
    return self.parseBinOp(parseBitXor, &.{.{ .token = .Pipe, .op = .BitOr }});
}

// Node allocation - simpler than manual create+assign
const ptr = try self.allocNode(value);        // Required node
const opt = try self.allocNodeOpt(maybe);     // Optional node
```

## Zig 0.15 Gotchas

```zig
// ArrayList: allocator in ALL methods
var list = std.ArrayList(T){};
defer list.deinit(allocator);
list.append(allocator, item);

// Enums: lowercase
.slice  // not .Slice
```

## Function Traits Framework (Secret Weapon)

**One analysis, many uses** - Build call graph once at comptime, query for all codegen decisions.

**Location:** `src/analysis/function_traits.zig`

### Current Traits

| Trait | Used For |
|-------|----------|
| `has_await` | Async strategy (state machine vs thread pool) |
| `has_io` | IO detection for async decisions |
| `mutates_params` | `var` vs `const` parameters |
| `can_error` | `!T` vs `T` return type |
| `needs_allocator` | Pass allocator or not |
| `is_pure` | Memoization / comptime eval |
| `is_tail_recursive` | Tail call optimization |
| `is_generator` | Generator state machine |
| `captured_vars` | Closure generation |
| `calls` | Call graph edges for DCE |

### IoFunctions (line 270)

Functions that trigger state machine async (actual I/O that benefits from kqueue):
- `sleep` - Timer I/O
- `read/write/open/close` - File I/O
- `get/post/fetch/connect/send/recv` - Network I/O
- `input` - stdin waits for user

**NOT** in IoFunctions (don't use state machine):
- `print` - synchronous, no benefit from polling
- `gather/wait/create_task/run` - coordination, not I/O

### Planned Enhancements (TODO: Implement)

**1. Effect System** - Foundation for parallelization & memoization
```zig
pub const Effects = struct {
    reads_global: bool,      // reads module-level var
    writes_global: bool,     // mutates module-level var
    does_io: bool,           // file/network/stdin/stdout
    allocates: bool,         // heap allocation
    throws: []ErrorType,     // PRECISE error types, not anyerror
    prints: bool,            // print() calls
};
```

**2. Escape Analysis** - Stack vs heap allocation (HUGE perf win)
```zig
escaping_params: []bool,              // which params escape scope?
escaping_locals: [][]const u8,        // which locals escape?
return_aliases_param: ?usize,         // return value aliases which param?
```

**3. Precise Error Types** - Smaller error unions, eliminate impossible catches
```zig
error_types: []ErrorType,  // IndexError, KeyError, etc.
// Instead of: fn foo() !i64  (anyerror)
// Generate:   fn foo() error{IndexError,KeyError}!i64
```

**4. Inlining Hints** - Inline small hot, skip large cold
```zig
estimated_size: usize,    // AST node count
call_sites: usize,        // how many callers?
inline_hint: enum { auto, always, never },
is_hot_path: bool,        // called in loop?
```

**5. Aliasing Analysis** - SIMD vectorization, safe parallelization
```zig
params_may_alias: [][]bool,  // NxN: can param[i] alias param[j]?
aliases_global: []bool,      // can param[i] alias a global?
```

**6. Loop Analysis** - Auto-vectorization, unrolling, parallel for
```zig
pub const LoopInfo = struct {
    depth: usize,
    bound: ?usize,        // static bound if known
    stride: ?i64,
    vectorizable: bool,   // no loop-carried deps?
    parallelizable: bool, // iterations independent?
};
```

**7. Type Narrowing** - Eliminate dispatch after isinstance()
```zig
pub const TypeGuard = struct {
    variable: []const u8,
    narrowed_to: []const u8,   // isinstance(x, int) -> "int"
    scope: struct { start: usize, end: usize },
};
```

### Query API

```zig
// Current - USE THESE IN CODEGEN!
anyAsyncHasIO(graph)                       // ANY async has I/O? → state machine for all
shouldUseStateMachineAsync(graph, "func")  // per-function async strategy
isParamMutated(graph, "func", 0)           // var vs const
needsErrorUnion(graph, "func")             // !T vs T
needsAllocator(graph, "func")              // allocator param
isPure(graph, "func")                      // memoization
canUseTCO(graph, "func")                   // tail call opt
isGenerator(graph, "func")                 // state machine
isDeadCode(graph, "func")                  // DCE

// Planned
canStackAllocate(graph, "func", "var")     // escape analysis
paramEscapes(graph, "func", idx)           // escape analysis
canParallelize(graph, "func")              // effect system
getExactErrors(graph, "func")              // precise errors
shouldInline(graph, "func")                // inlining
canVectorize(graph, "func")                // loop analysis
getTypeAt(graph, "func", "var", line)      // type narrowing
```

### Impact Matrix

| Analysis | Perf | Correctness | Code Size |
|----------|------|-------------|-----------|
| Escape Analysis | +++ | | - |
| Precise Errors | + | ++ | -- |
| Effect System | ++ | ++ | |
| Inlining | ++ | | +/- |
| Aliasing/SIMD | +++ | | |
| Loop Analysis | +++ | | |
| Type Narrowing | ++ | ++ | -- |

## Codegen Structure (AI-Optimized)

```
src/codegen/native/
├── dispatch/
│   ├── module_functions.zig    # Facade - imports from stdlib modules
│   ├── builtins.zig            # Builtin function dispatch
│   └── method_calls.zig        # Method call dispatch
├── builtins/
│   ├── conversions/            # int/float/str conversion handlers
│   ├── collections.zig         # list/dict/set builtins
│   └── math.zig                # math builtins
├── expressions/
│   ├── calls/                  # Call expression handlers
│   ├── operators/              # Operator handlers (arithmetic, comparison, etc.)
│   └── comprehensions.zig      # List/dict comprehensions
├── statements/
│   ├── assign/                 # Assignment handlers
│   ├── functions/
│   │   ├── generators.zig      # Function/class def generation
│   │   ├── param_analyzer.zig  # Parameter analysis
│   │   └── generators/
│   │       ├── builtin_types.zig  # Builtin base types (int, float, str)
│   │       ├── test_skip.zig      # Test skip detection for unittest
│   │       ├── signature.zig      # Function signature generation
│   │       └── body/              # Function/method body generation
│   │           ├── class_methods.zig
│   │           ├── function_gen.zig
│   │           └── mutation_analysis.zig
│   └── control/                # if/for/while/try
├── {json,re,os,math,...}.zig   # Stdlib module handlers (each <500 lines)
└── main.zig                    # NativeCodegen struct
```

## Analysis Structure

```
src/analysis/
├── function_traits.zig         # Call graph & unified function analysis (USE THIS!)
│   ├── analyzeNeedsAllocator() # Direct AST analysis for allocator
│   ├── analyzeUsesAllocatorParam() # Whether allocator param is actually used
│   └── Query API (needsAllocator, isPure, etc.)
├── native_types/               # Type inference
└── comptime_eval/              # Comptime value evaluation
```

Each stdlib module (json.zig, re.zig, etc.) exports:
```zig
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{...});
```

## Rules

- `--force` after code changes
- `defer deinit/free` for every allocation
- Module imports only (no `../../../`)
- `make benchmark-*` (no `time` command)
- **NO string-based type detection** - Never use `startsWith(u8, name, "__p_")` or similar patterns to detect variable types. Track type info explicitly during analysis phase instead.
- **NO skipping tests** - NEVER skip tests because we can't pass them. We MUST support 100% of Python features. The only legitimate skips are when the Python code itself has skip decorators (e.g., `@unittest.skipUnless`). If a test fails, FIX the underlying issue.
- **NEVER modify CPython tests** - The 390 test files in `tests/cpython/` are the original CPython unit tests. NEVER modify, simplify, or create alternative versions of these files. Fix the compiler to pass the original tests as-is.
- **NEVER use std.Thread** - BANNED! Always use metal0 async (`runtime.Scheduler`). CPU or I/O doesn't matter - metal0 auto-switches. See "metal0 async" section below.
- **HTTP/2 multiplexing** - Use `H2Connection.requestAll()` for parallel HTTP requests on a single connection instead of spawning threads per request.

## metal0 async (Auto I/O-CPU Switching)

**Automatic async mode selection based on workload type!**

metal0 analyzes code at compile time and AUTO-SWITCHES between two execution strategies:
- **I/O-bound**: State machine coroutines with kqueue netpoller (9,662x concurrency)
- **CPU-bound**: Thread pool with M:N scheduling (76% parallel efficiency, beats Go's 47%)

Say "use metal0 async" when you need concurrent/parallel execution.

### Key Files
| File | Purpose |
|------|---------|
| `src/codegen/native/async_state_machine.zig` | Transforms Python `async def` → Zig state machines |
| `packages/runtime/src/netpoller.zig` | kqueue/epoll for I/O events |
| `packages/runtime/src/EventLoop.zig` | Task queue, timers, thread pool |
| `packages/async_runtime/` | Runtime async support |
| `src/analysis/function_traits.zig` | Determines I/O vs CPU-bound at comptime |

### Auto Mode Selection

The compiler uses `function_traits.zig` to detect workload type:

```zig
// At compile time, metal0 checks:
if (anyAsyncHasIO(graph)) {
    // I/O detected → State machine + kqueue netpoller
    // 10,000 tasks × 100ms = 103.5ms total (9,662x concurrency)
} else {
    // CPU-bound → Thread pool + M:N scheduling
    // 8 workers × 50K hashes = 6.05x speedup (76% efficiency)
}
```

**IoFunctions** (trigger state machine mode):
- `sleep`, `read`, `write`, `open`, `close` - File/Timer I/O
- `get`, `post`, `fetch`, `connect`, `send`, `recv` - Network I/O
- `input` - stdin wait

**CPU-bound** (trigger thread pool mode):
- Pure computation (SHA256, fib, etc.)
- No I/O calls detected

### Usage Pattern

```zig
// For I/O-bound (state machine + netpoller)
const timer_id = runtime.netpoller.addTimer(duration_ns);
while (!runtime.netpoller.timerReady(timer_id)) {
    // Yields to other coroutines - 9,662x concurrency
}

// For CPU-bound (thread pool)
runtime.threadpool.spawn(fn, args);  // M:N scheduling across cores
```

### When to Use
- **Parallel I/O** - HTTP requests, file reads, timers (auto: state machine)
- **Parallel CPU** - Hash computation, math (auto: thread pool)
- **asyncio.gather** - Wait for multiple coroutines
- **High concurrency** - 9,662x for I/O, 76% efficiency for CPU

### Benchmarks

| Workload | metal0 | Go | Rust | CPython |
|----------|--------|-----|------|---------|
| I/O (10K × 100ms sleep) | 103.5ms (9,662x) | 126.9ms | 111.7ms | 194.3ms |
| CPU (8 × 50K SHA256) | 6.05x speedup | 3.72x | 1.04x | 1.07x |

### Netpoller for I/O
```zig
const timer_id = runtime.netpoller.addTimer(duration_ns);
if (!runtime.netpoller.timerReady(timer_id)) return null; // yield to other tasks
```


## Auto-Generated Index

> Last updated: 2025-11-29 12:53
> Run `continue` to refresh this index

### Helpers

- `allocNode` :148
- `allocNodeOpt` :156
- `parseBinOp` :173

- async_runtime: 6 functions
- c_interop: 50 functions
- metal: 6 functions
- regex: 287 functions
- runtime: 1246 functions
- threading: 17 functions
- token_optimizer: 29 functions
- tokenizer: 463 functions

### Patterns

- Arena Allocator: 9 usages
  - src/analysis/native_types/inferrer.zig:30:        arena.* = std.heap.ArenaAllocator.init(allocator);
  - src/import_scanner.zig:287:    var arena = std.heap.ArenaAllocator.init(allocator);
  - src/codegen/native/main/imports.zig:46:    var arena = std.heap.ArenaAllocator.init(allocator);
- errdefer cleanup: 197 usages
- Custom allocator: @import("allocator_helper")
- Custom hashmap: @import("hashmap_helper")


### Modules

- @import("hashmap_helper")
- @import("allocator_helper")
- @import("collections")
- @import("fnv_hash")
- @import("zig_keywords")
- @import("ast")
- @import("gzip")
- @import("json")
- @import("json_simd")
- @import("regex")
- @import("function_traits") - Call graph & function analysis (secret weapon)

- src/
- src/analysis/
- src/analysis/comptime_eval/
- src/analysis/native_types/
- src/ast/
- src/codegen/
- src/codegen/native/
- src/import_resolver/
- src/lexer/
- src/lexer/tokenizer/
- src/main/
- src/main/compile/
- src/parser/
- src/parser/expressions/
- src/parser/postfix/

!IMPORTANT! always go for the proper fix, Say NO to simpler approach that is not a proper fix.
!IMPORTANT! fix memory leaks immediately!
!IMPORTANT! less coce is good code
!IMPORTANT! FUCK "simpler solutions"
!IMPORTANT! if there is build error not cause by you, just sleep 30s to wait for other agent finish their work