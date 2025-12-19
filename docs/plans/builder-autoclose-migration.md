# ZigBuilder Auto-Close Migration Plan

## Problem Statement

Even with `emitConst`/`emitFmtConst` helpers, codegen is error-prone because **brackets/braces/parentheses must be manually matched**:

```zig
// CURRENT - easy to mismatch
try emitConst(self, "(");
try self.genExpr(left);
try emitConst(self, " + ");
try self.genExpr(right);
try emitConst(self, ")");  // Easy to forget or mismatch!
```

## Goal

Create callback-based auto-closing helpers that **guarantee matching**:

```zig
// DESIRED - impossible to mismatch
try self.emitBinOp(left, " + ", right);  // Auto-wraps in ()
```

## Current State (as of 2024-12)

| Component | Status | Notes |
|-----------|--------|-------|
| `emitConst` in module files | ✅ 85/85 | Reduces boilerplate but no auto-close |
| `withInlineBlock` | ✅ 81 files | Auto-closes labeled blocks `(__m{id}: { ... })` |
| `mod_helper.zig` patterns | ✅ Done | `wrapBlk`, `wrap2Blk`, etc. |
| Auto-close `()` parens | ✅ Done | `withParens`, `emitParens`, `emitBinOp` |
| Auto-close `{}` braces | ✅ Done | `withBraces`, `withStructLit` |
| Auto-close `[]` brackets | ✅ Done | `withBrackets`, `emitSubscript`, `emitSlice` |

## Implementation Plan

### Phase 1: Core Auto-Close Helpers (in `main/core.zig`) ✅ DONE

Added these methods to `NativeCodegen` in `src/codegen/native/main/core.zig`:

**Basic auto-close (callback-based):**
```zig
withParens(body_fn)           // ( ... )
withParensCtx(ctx, body_fn)   // ( ... ) with context
withBraces(body_fn)           // { ... }
withBracesCtx(ctx, body_fn)   // { ... } with context
withBrackets(body_fn)         // [ ... ]
withBracketsCtx(ctx, body_fn) // [ ... ] with context
withStructLit(body_fn)        // .{ ... }
withStructLitCtx(ctx, body_fn)// .{ ... } with context
```

**Convenience helpers (direct AST node):**
```zig
emitParens(expr)              // (expr)
emitBinOp(left, op, right)    // (left op right)
emitCall(name, body_fn)       // name(...)
emitCallCtx(name, ctx, body)  // name(...) with context
emitIfExpr(cond, then, else)  // if (cond) then else else
emitTry(expr)                 // try expr
emitOrelse(expr, default)     // expr orelse default
emitCatch(expr, default)      // expr catch default
emitSlice(val, start, end)    // val[start..end]
emitSubscript(val, index)     // val[index]
emitField(val, field)         // val.field
emitExprList(exprs)           // expr1, expr2, ...
```

### Phase 2: Migrate High-Impact Files (IN PROGRESS)

Priority order (by complexity and usage):

1. ✅ **expressions/operators/power_div_ops.zig** - Power, division, modulo ops (commit f6e75e05)
2. ✅ **expressions/operators/arithmetic.zig** - Binary ops dispatcher (commit 17032ecc)
3. ✅ **expressions/operators/comparison.zig** - Comparison ops (commit 76b00b39)
4. ✅ **expressions/operators/logical.zig** - `and`, `or`, `not` (commit d5e8732c)
5. ✅ **expressions/subscript.zig** - Array/dict subscripting (commit 5dbe9f6e)
6. ✅ **expressions/calls.zig** - Function calls (commit d640ba8b)
7. ✅ **statements/control/conditionals.zig** - No migration needed (no bracket patterns)
8. ✅ **statements/control/loops/*.zig** - Minimal patterns already safe

### Phase 3: Migrate Remaining Files (IN PROGRESS)

Priority operator files:
1. ✅ **expressions/operators/unary_ops.zig** - Unary operations (commit 6bcd181a)
2. ✅ **expressions/operators/unified_int_ops.zig** - UnifiedInt/Complex ops (commit 6bcd181a)
3. ✅ **expressions/operators/collection_ops.zig** - Collection ops (commit 44a71bb1)

Remaining files (~80) in:
- `expressions/` (23 files)
- `statements/` (28 files)
- `builtins/` (12 files)
- `methods/` (8 files)

## Migration Patterns

### Pattern 1: Simple expression wrapping
```zig
// BEFORE
try emitConst(self, "(");
try self.genExpr(expr);
try emitConst(self, ")");

// AFTER
try self.emitParens(expr);
```

### Pattern 2: Binary operations
```zig
// BEFORE
try emitConst(self, "(");
try self.genExpr(left);
try emitConst(self, " + ");
try self.genExpr(right);
try emitConst(self, ")");

// AFTER
try self.emitBinOp(left, " + ", right);
```

### Pattern 3: Function calls
```zig
// BEFORE
try emitConst(self, "std.math.max(");
try self.genExpr(a);
try emitConst(self, ", ");
try self.genExpr(b);
try emitConst(self, ")");

// AFTER (with emitExprList)
try self.emitCall("std.math.max", struct {
    pub fn f(c: *NativeCodegen) !void {
        try c.emitExprList(&.{ a, b });
    }
}.f);

// OR simpler for 2 args:
try emitConst(self, "std.math.max");
try self.withParens(struct {
    pub fn f(c: *NativeCodegen) !void {
        try c.genExpr(a);
        try emitConst(c, ", ");
        try c.genExpr(b);
    }
}.f);
```

### Pattern 4: Subscript/slice
```zig
// BEFORE
try self.genExpr(value);
try emitConst(self, "[");
try self.genExpr(index);
try emitConst(self, "]");

// AFTER
try self.emitSubscript(value, index);

// For slices:
try self.emitSlice(value, start_opt, end_opt);
```

### Pattern 5: Struct literals
```zig
// BEFORE
try emitConst(self, ".{ .x = ");
try self.genExpr(x);
try emitConst(self, ", .y = ");
try self.genExpr(y);
try emitConst(self, " }");

// AFTER
try self.withStructLit(struct {
    pub fn f(c: *NativeCodegen) !void {
        try emitConst(c, ".x = ");
        try c.genExpr(x);
        try emitConst(c, ", .y = ");
        try c.genExpr(y);
    }
}.f);
```

## How to Migrate a File

1. **Find bracket patterns**:
   ```bash
   grep -n 'emitConst.*"("' file.zig | head -20
   ```

2. **Replace each pattern** using the examples above

3. **Test**: `zig build && ./zig-out/bin/metal0 test tests/cpython longexp`

4. **Commit**: One file per commit for easy rollback

## Verification Checklist

After migration, these patterns should NOT exist in migrated files:

- [ ] No bare `"("` followed later by bare `")"`
- [ ] No bare `"{"` followed later by bare `"}"`
- [ ] No bare `"["` followed later by bare `"]"`

## Files to Track

### Completed (with auto-close)
- (none yet - Phase 1 not started)

### In Progress
- (none)

### Remaining (94 core codegen files)
```
expressions/operators/arithmetic.zig
expressions/operators/comparison.zig
expressions/operators/logical.zig
... (see full list from grep output)
```

## Success Criteria

1. **Zero manual bracket matching** in migrated files
2. **Build passes** after each file migration
3. **Tests pass** (longexp as smoke test)
4. **Code is shorter** (callback pattern is more concise)

## Notes

- The callback pattern uses Zig's anonymous struct trick for closures
- For simple cases, add convenience helpers like `emitParens(expr)`
- Keep `emitConst` for non-bracketed output (strings, operators, keywords)
- `withInlineBlock` is already the pattern for labeled blocks - extend same approach
