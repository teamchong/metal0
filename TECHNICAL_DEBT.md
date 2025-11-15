# Technical Debt

This document tracks known technical debt and areas for future improvement.

---

## Code Organization

### File Size Limits (Target: < 500 lines)

**Issue:** Several codegen files exceed the 500-line target for maintainability.

| File | Lines | Target | Over Limit |
|:---|---:|---:|---:|
| `src/codegen/classes.zig` | 949 | 500 | +449 (90%) |
| `src/codegen/functions.zig` | 709 | 500 | +209 (42%) |
| `src/codegen/statements.zig` | 697 | 500 | +197 (39%) |
| `src/codegen/expressions.zig` | 685 | 500 | +185 (37%) |
| `src/codegen/builtins.zig` | 610 | 500 | +110 (22%) |

**Impact:**
- Harder to navigate and understand
- Increases merge conflicts in multi-contributor environment
- Slows down incremental compilation

**Proposed Solution:**
Split into smaller, focused modules:
- `classes.zig` → `classes/`, `methods.zig`, `inheritance.zig`, `attributes.zig`
- `functions.zig` → `functions/`, `calls.zig`, `returns.zig`
- `statements.zig` → `statements/`, `assignments.zig`, `imports.zig`
- `expressions.zig` → `expressions/`, `binops.zig`, `unaryops.zig`
- `builtins.zig` → `builtins/`, `string_builtins.zig`, `list_builtins.zig`

**Priority:** Medium (affects maintainability, not functionality)

---

## Performance Issues

### 1. String Concatenation in Tight Loops

**Issue:** Complex expressions like `a + b + c + d` create intermediate temporary objects.

**Example:**
```python
for i in range(400000000):
    result = a + b + c + d  # Creates 3 temporaries per iteration
```

**Generated Code:**
```zig
const __expr0 = try runtime.PyString.concat(allocator, a, b);  // Temp 1
defer runtime.decref(__expr0, allocator);
const __expr1 = try runtime.PyString.concat(allocator, __expr0, c);  // Temp 2
defer runtime.decref(__expr1, allocator);
result = try runtime.PyString.concat(allocator, __expr1, d);  // Final
```

**Impact:** For 400M iterations = 1.2 billion allocations

**Proposed Solutions:**
1. **Expression optimization pass:** Detect chains and emit single concat call
2. **String builder pattern:** Use `std.ArrayList(u8)` for concatenation chains
3. **Compile-time evaluation:** Evaluate constant string expressions at compile time

**Priority:** High (affects common use case)

---

### 2. NumPy FFI Overhead

**Issue:** Python C API calls have significant overhead compared to native Python imports.

**Impact:** NumPy operations slower than CPython

**Proposed Solutions:**
1. Lazy Python initialization (avoid 50ms startup)
2. Cache NumPy module imports
3. Direct NumPy C API usage (bypass Python layer)
4. Detect pure-NumPy sections and skip compilation

**Priority:** Medium (affects NumPy users only)

---

## Memory Management

### Removed Decref Before Reassignment

**Change:** Removed automatic `decref` before string reassignments in loops.

**Before:**
```zig
while (i < n) {
    runtime.decref(result, allocator);  // Freed every iteration
    result = try runtime.PyString.concat(allocator, a, b);
    i += 1;
}
```

**After:**
```zig
while (i < n) {
    result = try runtime.PyString.concat(allocator, a, b);  // Leak intermediate values
    i += 1;
}
defer runtime.decref(result, allocator);  // Only free final value
```

**Trade-off:**
- ✅ **Pro:** Massive performance improvement (eliminates N allocations)
- ⚠️ **Con:** Leaks intermediate values until loop exit
- ⚠️ **Con:** Large loops may accumulate memory

**Future Solution:**
- Smart escape analysis to detect when decref is safe
- Use arena allocator for loop-local temporaries
- Employ comptime analysis to align with Python's reference counting timeline

**Priority:** High (current behavior may cause OOM in extreme cases)

---

## Compiler Features

### Comptime and GC Alignment

**TODO:** Use Zig's `comptime` to align memory management with Python's reference counting timeline.

**Goal:**
- Analyze variable lifetimes at compile time
- Generate optimal decref points
- Minimize allocations without memory leaks

**Priority:** Medium (requires advanced compiler analysis)

---

## Testing

### Test Coverage

**Current:** 101/142 tests passing (71.1%)

**Areas needing tests:**
- String concatenation edge cases
- Memory leak detection for tight loops
- NumPy FFI error handling
- Large iteration counts (stress testing)

**Priority:** Medium

---

## Documentation

### Missing Documentation

- [ ] Performance optimization guide
- [ ] Memory management best practices
- [ ] When to use PyAOT vs CPython
- [ ] NumPy integration limitations

**Priority:** Low (functionality complete, docs needed)

---

## License

Apache 2.0
