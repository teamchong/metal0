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
try self.withParens(fn (c) {
    try c.genExpr(left);
    try c.emit(" + ");
    try c.genExpr(right);
});  // Auto-closes with )
```

## Current State (as of 2024-12)

| Component | Status | Notes |
|-----------|--------|-------|
| `emitConst` in module files | ✅ 85/85 | Reduces boilerplate but no auto-close |
| `withInlineBlock` | ✅ 81 files | Auto-closes labeled blocks `(__m{id}: { ... })` |
| `mod_helper.zig` patterns | ✅ Done | `wrapBlk`, `wrap2Blk`, etc. |
| Auto-close `()` parens | ❌ Missing | Need for expressions |
| Auto-close `{}` braces | ❌ Missing | Need for statements |
| Auto-close `[]` brackets | ❌ Missing | Need for subscripts |

## Implementation Plan

### Phase 1: Core Auto-Close Helpers (in `main/core.zig`)

Add these methods to `NativeCodegen`:

```zig
/// Auto-close parentheses: ( ... )
pub fn withParens(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, "(");
    try body_fn(self);
    try emitConst(self, ")");
}

/// Auto-close braces: { ... }
pub fn withBraces(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, "{ ");
    try body_fn(self);
    try emitConst(self, " }");
}

/// Auto-close brackets: [ ... ]
pub fn withBrackets(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, "[");
    try body_fn(self);
    try emitConst(self, "]");
}

/// Auto-close angle brackets for type params: < ... >
/// Note: Zig doesn't use <>, but useful for generic patterns
pub fn withAngle(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, "<");
    try body_fn(self);
    try emitConst(self, ">");
}

/// Emit binary operation with auto-parens: (left op right)
pub fn withBinOp(self: *NativeCodegen, left: ast.Node, op: []const u8, right: ast.Node) !void {
    try emitConst(self, "(");
    try self.genExpr(left);
    try emitConst(self, op);
    try self.genExpr(right);
    try emitConst(self, ")");
}

/// Emit function call: name(args...)
pub fn withCall(self: *NativeCodegen, name: []const u8, body_fn: anytype) !void {
    try emitConst(self, name);
    try emitConst(self, "(");
    try body_fn(self);
    try emitConst(self, ")");
}

/// Emit struct literal: .{ ... }
pub fn withStructLit(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, ".{ ");
    try body_fn(self);
    try emitConst(self, " }");
}

/// Emit array literal: .{ ... } (same as struct but semantic difference)
pub fn withArrayLit(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, ".{ ");
    try body_fn(self);
    try emitConst(self, " }");
}

/// Emit if expression: if (cond) then_val else else_val
pub fn withIfExpr(self: *NativeCodegen, cond_fn: anytype, then_fn: anytype, else_fn: anytype) !void {
    try emitConst(self, "if (");
    try cond_fn(self);
    try emitConst(self, ") ");
    try then_fn(self);
    try emitConst(self, " else ");
    try else_fn(self);
}

/// Emit try expression: try expr
pub fn withTry(self: *NativeCodegen, body_fn: anytype) !void {
    try emitConst(self, "try ");
    try body_fn(self);
}

/// Emit catch expression: expr catch default
pub fn withCatch(self: *NativeCodegen, expr_fn: anytype, default: []const u8) !void {
    try expr_fn(self);
    try emitConst(self, " catch ");
    try emitConst(self, default);
}
```

### Phase 2: Migrate High-Impact Files

Priority order (by complexity and usage):

1. **expressions/operators/arithmetic.zig** - Binary ops like `+`, `-`, `*`, `/`
2. **expressions/operators/comparison.zig** - Comparison ops
3. **expressions/operators/logical.zig** - `and`, `or`, `not`
4. **expressions/subscript.zig** - Array/dict subscripting
5. **expressions/calls.zig** - Function calls
6. **statements/control/conditionals.zig** - if/else
7. **statements/control/loops/*.zig** - for/while loops

### Phase 3: Migrate Remaining Files

After core files are done, migrate remaining ~80 files in:
- `expressions/` (23 files)
- `statements/` (28 files)
- `builtins/` (12 files)
- `methods/` (8 files)

## Migration Pattern

For each file:

1. **Identify bracket patterns**:
   ```bash
   grep -n 'emitConst.*"("' file.zig
   grep -n 'emitConst.*"{"' file.zig
   grep -n 'emitConst.*"\\["' file.zig
   ```

2. **Replace with callback**:
   ```zig
   // BEFORE
   try emitConst(self, "(");
   try self.genExpr(expr);
   try emitConst(self, ")");

   // AFTER
   try self.withParens(struct {
       expr: ast.Node,
       fn call(c: *NativeCodegen) !void {
           try c.genExpr(@This().expr);  // Capture via @This()
       }
   }{ .expr = expr }.call);

   // OR simpler for single expressions:
   try self.emitParens(expr);  // Helper that just wraps genExpr
   ```

3. **Test**: Run `zig build` and `metal0 test tests/cpython longexp`

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
