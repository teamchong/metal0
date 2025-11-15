# Multi-Pass Compilation Design

**Goal:** Use Zig's `comptime` and multi-pass analysis to optimize string operations and memory management.

---

## Current Problems

### 1. String Concatenation Creates Temporaries

**Current behavior:**
```python
result = a + b + c + d  # 4 strings
```

**Generated code (BAD):**
```zig
const __expr0 = try runtime.PyString.concat(allocator, a, b);  // Alloc 1
defer runtime.decref(__expr0, allocator);
const __expr1 = try runtime.PyString.concat(allocator, __expr0, c);  // Alloc 2
defer runtime.decref(__expr1, allocator);
result = try runtime.PyString.concat(allocator, __expr1, d);  // Alloc 3
```

**In a loop with 400M iterations = 1.2 BILLION allocations!**

### 2. Unnecessary Memory Allocation

**Current behavior:**
```python
for i in range(1000000):
    result = a + b  # Reassignment in loop
```

**Generated code (BAD):**
```zig
while (i < 1000000) {
    // Old 'result' is leaked until loop exit
    result = try runtime.PyString.concat(allocator, a, b);  // 1M allocations
    i += 1;
}
defer runtime.decref(result, allocator);  // Only frees LAST value
```

**1M allocations, but only last one is freed. Other 999,999 values leak until scope exit!**

---

## Solution: Multi-Pass Compilation with Comptime Analysis

### Architecture Overview

```
Python Source
    ↓
[Pass 1] Lexer → Tokens
    ↓
[Pass 2] Parser → AST
    ↓
[Pass 3] 🆕 Semantic Analysis (comptime)
    • Variable lifetime analysis
    • Expression chain detection
    • Loop pattern recognition
    • Reference counting timeline
    ↓
[Pass 4] 🆕 Optimization Pass
    • Expression chain optimization
    • Smart memory management
    • Arena allocator insertion
    ↓
[Pass 5] Code Generation → Optimized Zig
    ↓
[Pass 6] Zig Compiler → Native Binary
```

---

## Pass 3: Semantic Analysis (NEW)

### 3.1 Variable Lifetime Analysis

**Goal:** Determine when variables are last used, not just when they go out of scope.

**Example:**
```python
def foo():
    x = "hello"
    y = x + " world"  # x last used here
    print(y)
    # x still in scope but never used again
```

**Analysis output:**
```zig
// Comptime analysis result:
// Variable: x
//   - Created: line 2
//   - Last used: line 3
//   - Scope ends: line 5
//   - Can decref early: YES (after line 3)
```

**Data structure:**
```zig
const VariableLifetime = struct {
    name: []const u8,
    first_assignment: usize,  // Line number
    last_use: usize,          // Line number
    scope_end: usize,         // Line number
    is_loop_local: bool,      // Defined and only used in loop
    reassignment_count: usize, // How many times reassigned
};
```

### 3.2 Expression Chain Detection

**Goal:** Detect chains of binary operations that can be optimized.

**Pattern:**
```python
result = a + b + c + d
```

**Detection:**
```zig
const ExpressionChain = struct {
    op: ast.Operator,  // e.g., .Add for string concat
    operands: []ast.Node,  // [a, b, c, d]
    is_string_concat: bool,
    chain_length: usize,  // 4
};
```

**Analysis:**
- Detect: `BinOp(Add, BinOp(Add, BinOp(Add, a, b), c), d)`
- Flatten to: `[a, b, c, d]`
- Emit optimized: `runtime.PyString.concatMulti(allocator, &[_]*PyObject{a, b, c, d})`

### 3.3 Loop Pattern Recognition

**Goal:** Identify patterns in loops for special handling.

**Patterns to detect:**
1. **Loop-local temporaries:** Variables created and used only within loop
2. **Loop-invariant values:** Values that don't change across iterations
3. **Accumulator patterns:** Variable that accumulates results

**Example:**
```python
for i in range(1000000):
    temp = expensive_operation()  # Loop-local temporary
    result = result + temp        # Accumulator
```

**Analysis:**
```zig
const LoopAnalysis = struct {
    loop_local_vars: [][]const u8,  // ["temp"]
    accumulators: [][]const u8,     // ["result"]
    invariants: [][]const u8,       // []
    iteration_count: ?i64,          // 1000000 (if comptime known)
};
```

---

## Pass 4: Optimization Pass (NEW)

### 4.1 Expression Chain Optimization

**Transform:**
```python
result = a + b + c + d
```

**Instead of:**
```zig
const __expr0 = try runtime.PyString.concat(allocator, a, b);
defer runtime.decref(__expr0, allocator);
const __expr1 = try runtime.PyString.concat(allocator, __expr0, c);
defer runtime.decref(__expr1, allocator);
result = try runtime.PyString.concat(allocator, __expr1, d);
```

**Generate:**
```zig
// Single allocation, single operation
result = try runtime.PyString.concatMulti(allocator, &[_]*PyObject{a, b, c, d});
```

**Implementation in runtime.zig:**
```zig
pub fn concatMulti(allocator: std.mem.Allocator, strings: []*PyObject) !*PyObject {
    // Calculate total length
    var total_len: usize = 0;
    for (strings) |s| {
        total_len += PyString.getValue(s).len;
    }

    // Single allocation
    var result_buf = try allocator.alloc(u8, total_len);

    // Copy all strings
    var offset: usize = 0;
    for (strings) |s| {
        const str_val = PyString.getValue(s);
        @memcpy(result_buf[offset..offset + str_val.len], str_val);
        offset += str_val.len;
    }

    return try PyString.fromOwnedSlice(allocator, result_buf);
}
```

**Result:** 1 allocation instead of 3!

### 4.2 Arena Allocator for Loop-Local Temporaries

**Problem:**
```python
for i in range(1000000):
    temp1 = a + b
    temp2 = temp1 + c
    result = temp2 + d
```

**Current:** 3M allocations (3 per iteration × 1M iterations)

**Solution:** Use arena allocator for loop-local temporaries

**Generated code:**
```zig
// Create arena for loop
var loop_arena = std.heap.ArenaAllocator.init(allocator);
defer loop_arena.deinit();  // Frees ALL loop temporaries at once
const loop_allocator = loop_arena.allocator();

var i: i64 = 0;
while (i < 1000000) {
    // Use loop_allocator for temporaries
    const temp1 = try runtime.PyString.concat(loop_allocator, a, b);
    // NO defer needed - arena frees everything
    const temp2 = try runtime.PyString.concat(loop_allocator, a, b);
    result = try runtime.PyString.concat(allocator, temp2, d);  // Keep result outside arena

    i += 1;

    // Arena reset every N iterations to prevent memory growth
    if (i % 10000 == 0) {
        _ = loop_arena.reset(.retain_capacity);
    }
}
```

**Result:** Temporaries freed in bulk, MUCH faster!

### 4.3 Smart Decref Placement

**Goal:** Place `decref` at last use, not at scope end.

**Analysis:**
```python
def foo():
    x = create_large_object()  # 100MB
    y = process(x)             # x last used here
    # ... 1000 lines of code ...
    return y
    # x still in scope, holding 100MB
```

**Current (BAD):**
```zig
const x = try createLargeObject(allocator);
defer runtime.decref(x, allocator);  // Waits until function exit!
const y = try process(allocator, x);
defer runtime.decref(y, allocator);
// ... 1000 lines ...
return y;
// x finally freed here (too late!)
```

**Optimized (GOOD):**
```zig
const x = try createLargeObject(allocator);
const y = try process(allocator, x);
runtime.decref(x, allocator);  // Free immediately after last use!
defer runtime.decref(y, allocator);
// ... 1000 lines ...
return y;
```

**Implementation:**
Using lifetime analysis from Pass 3, insert `decref` right after last use instead of using `defer`.

---

## Implementation Plan

### Phase 1: Foundation (Week 1)

**Files to create:**
```
src/analysis/
├── lifetime.zig       # Variable lifetime analysis
├── expressions.zig    # Expression chain detection
├── loops.zig          # Loop pattern recognition
└── analyzer.zig       # Main analysis orchestrator
```

**New struct in codegen:**
```zig
pub const SemanticInfo = struct {
    lifetimes: std.StringHashMap(VariableLifetime),
    expr_chains: std.ArrayList(ExpressionChain),
    loop_info: std.ArrayList(LoopAnalysis),
};
```

### Phase 2: Optimization Pass (Week 2)

**Files to modify:**
```
src/codegen/expressions.zig  # Add chain optimization
src/codegen/statements.zig   # Add smart decref
src/codegen/control_flow.zig # Add arena for loops
```

**Files to create:**
```
src/optimizer/
├── expressions.zig    # Expression chain optimizer
├── memory.zig         # Memory management optimizer
└── optimizer.zig      # Main optimizer orchestrator
```

### Phase 3: Runtime Support (Week 3)

**Add to runtime:**
```zig
// packages/runtime/src/pystring.zig
pub fn concatMulti(allocator: std.mem.Allocator, strings: []*PyObject) !*PyObject { ... }

// packages/runtime/src/runtime.zig
pub fn createArenaForLoop(base_allocator: std.mem.Allocator) std.heap.ArenaAllocator { ... }
```

### Phase 4: Testing (Week 4)

**New benchmarks:**
```python
# benchmarks/string_chain.py - Test expression chains
result = a + b + c + d + e + f  # 6-way concat

# benchmarks/loop_temps.py - Test arena allocator
for i in range(1000000):
    temp = a + b
    result = temp + c
```

**Expected improvements:**
- String chain: 6 allocations → 1 allocation (6x faster)
- Loop temps: 2M allocations → 100 allocations (20,000x less memory pressure)

---

## Comptime Usage in Zig

**Key insight:** We can use `comptime` in the codegen itself!

```zig
fn optimizeExpressionChain(
    comptime chain: ExpressionChain,  // Analyzed at compile time
    allocator: std.mem.Allocator
) ![]const u8 {
    comptime {
        if (chain.is_string_concat and chain.chain_length > 2) {
            // Generate optimized code for multi-concat
            return generateConcatMulti(chain);
        } else {
            // Generate normal code
            return generateNormalConcat(chain);
        }
    }
}
```

---

## Expected Performance Improvements

### String Concatenation

**Before:**
```python
for i in range(400000000):
    result = a + b + c + d
```
- Allocations: 1.2 billion
- Time: >10 minutes (timeout)

**After:**
```python
for i in range(400000000):
    result = a + b + c + d
```
- Allocations: 400 million (1 per iteration)
- Time: ~5 seconds (estimated)
- **Speedup: 120x faster, matching or beating CPython!**

### Memory Usage

**Loop with temporaries:**
```python
for i in range(1000000):
    temp1 = a + b
    temp2 = c + d
    result = temp1 + temp2
```

**Before:**
- Allocations: 3 million
- Peak memory: 3 million strings in memory

**After:**
- Allocations: 1 million (for result only)
- Peak memory: 10,000 strings (arena resets every 10k iterations)
- **Memory reduction: 300x less!**

---

## Timeline

**Estimated effort:** 4 weeks for full implementation

| Week | Task | Impact |
|:---|:---|:---|
| 1 | Semantic analysis pass | Foundation |
| 2 | Optimization pass | Code structure |
| 3 | Runtime support | Performance |
| 4 | Testing & benchmarks | Validation |

**Quick wins (can be done first):**
1. Expression chain optimization (3 days) → Fix string concat benchmark
2. Arena allocator for loops (2 days) → Massive memory reduction

---

## Success Metrics

**Target benchmarks:**

| Benchmark | Current | Target | Improvement |
|:---|---:|---:|---:|
| String concat (400M) | Timeout | 5-10s | ∞ → 120x faster |
| NumPy FFI (32M) | Timeout | 30-60s | Better than CPython |

**When complete:**
- All benchmarks run successfully
- Memory usage controlled in tight loops
- Performance competitive with or better than CPython for all patterns

---

## License

Apache 2.0
