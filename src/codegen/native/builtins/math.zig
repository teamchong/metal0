/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// Math helpers - auto-closing patterns
// ============================================

/// Emit method call suffix: .methodName(
fn emitMethodStart(self: *NativeCodegen, method: []const u8) CodegenError!void {
    try emitConst(self, ".");
    try emitConst(self, method);
    try emitConst(self, "(");
}

/// Emit @builtin call start: @builtinName(
fn emitBuiltinStart(self: *NativeCodegen, builtin: []const u8) CodegenError!void {
    try emitConst(self, "@");
    try emitConst(self, builtin);
    try emitConst(self, "(");
}

/// Check if argument is None constant
fn isNoneArg(arg: ast.Node) bool {
    if (arg == .constant) {
        if (arg.constant.value == .none) return true;
    }
    if (arg == .name) {
        if (std.mem.eql(u8, arg.name.id, "None")) return true;
    }
    return false;
}

/// Check if an expression is uncertain (needs PyValue)
/// Two-Flow: routes uncertain types to PyValue methods
/// CONSERVATIVE: Only returns true for explicitly PyValue or unknown typed variables
/// Does NOT use confidence fallback to avoid false positives on unset confidence
fn isExprUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr == .name) {
        const name = expr.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            return vt == .pyvalue or vt == .unknown;
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

/// Generate code for abs(n)
/// Returns absolute value
/// Two-Flow: routes uncertain operands to PyValue.pyAbs()
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // abs() requires exactly one argument - generate an error union for assertRaises
        try emitConst(self, "(error.TypeError)");
        return;
    }

    // Two-Flow: Check if argument is uncertain
    if (isExprUncertain(self, args[0])) {
        // Route to PyValue.pyAbs() for runtime type safety
        try self.genExpr(args[0]);
        try emitConst(self, ".pyAbs()");
        return;
    }

    // Check if arg is a bool - need to cast to int first since @abs doesn't work on bool
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isBoolean(arg_type)) {
        // abs(True) = 1, abs(False) = 0
        // Just convert bool to int: @intFromBool(...)
        try emitConst(self, "@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try emitConst(self, "))");
        return;
    }

    // Generate: @abs(n)
    try emitBuiltinStart(self, "abs");
    try self.genExpr(args[0]);
    try emitConst(self, ")");
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
/// Two-Flow: routes uncertain operands to PyValue.pyMin()
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: min([1, 2, 3]) or min(some_sequence)
        // Use runtime function that handles any iterable
        try emitConst(self, "runtime.builtins.minIterable(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (isExprUncertain(self, arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMin() chained for runtime type safety
        // min(a, b, c) => a.pyMin(b).pyMin(c)
        try self.genExpr(args[0]);
        for (args[1..]) |arg| {
            try emitMethodStart(self, "pyMin");
            try self.genExpr(arg);
            try emitConst(self, ")");
        }
        return;
    }

    // Generate: @min(a, @min(b, c))
    try emitBuiltinStart(self, "min");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try emitConst(self, ", ");
        try self.genExpr(arg);
    }
    try emitConst(self, ")");
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
/// Two-Flow: routes uncertain operands to PyValue.pyMax()
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: max([1, 2, 3]) or max(some_sequence)
        // Use runtime function that handles any iterable
        try emitConst(self, "runtime.builtins.maxIterable(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (isExprUncertain(self, arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMax() chained for runtime type safety
        // max(a, b, c) => a.pyMax(b).pyMax(c)
        try self.genExpr(args[0]);
        for (args[1..]) |arg| {
            try emitMethodStart(self, "pyMax");
            try self.genExpr(arg);
            try emitConst(self, ")");
        }
        return;
    }

    // Generate: @max(a, @max(b, c))
    try emitBuiltinStart(self, "max");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try emitConst(self, ", ");
        try self.genExpr(arg);
    }
    try emitConst(self, ")");
}

/// Generate code for round(n) or round(n, ndigits)
/// Rounds to nearest integer or specified decimal places
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "@as(f64, 0.0)");
        return;
    }

    // round(n) or round(n, None) - round to nearest integer
    if (args.len == 1 or (args.len == 2 and isNoneArg(args[1]))) {
        // Use runtime.builtins.pyRound to handle both int and float
        try emitConst(self, "runtime.builtins.pyRound(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places
    // Use runtime round function to handle both int and float values
    try emitConst(self, "(try runtime.builtins.round(");
    try self.genExpr(args[0]);
    try emitConst(self, ", .{");
    try self.genExpr(args[1]);
    try emitConst(self, "}))");
}

/// Generate code for pow(base, exp) or pow(base, exp, mod)
/// Returns base^exp or base^exp % mod (modular exponentiation)
/// Uses runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    if (args.len == 3) {
        // pow(base, exp, mod) - modular exponentiation
        // Generate: @rem(@as(i64, @intFromFloat(std.math.pow(f64, base, exp))), mod)
        try emitConst(self, "@rem(@as(i64, @intFromFloat(std.math.pow(f64, @as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try emitConst(self, ")), @as(f64, @floatFromInt(");
        try self.genExpr(args[1]);
        try emitConst(self, "))))), ");
        try self.genExpr(args[2]);
        try emitConst(self, ")");
    } else {
        // pow(base, exp) - standard power
        // Use runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
        try emitConst(self, "(try runtime.builtins.pow.call(");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, "))");
    }
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    // Generate: &[_]u8{@intCast(n)}
    try emitConst(self, "&[_]u8{@intCast(");
    try self.genExpr(args[0]);
    try emitConst(self, ")}");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    // Need extra parens when arg is a slice subscript (generates labeled block)
    const needs_parens = args[0] == .subscript and args[0].subscript.slice == .slice;
    try emitConst(self, "@as(i64, ");
    if (needs_parens) try emitConst(self, "(");
    try self.genExpr(args[0]);
    if (needs_parens) try emitConst(self, ")");
    try emitConst(self, "[0])");
}

/// Generate code for divmod(a, b)
/// Returns tuple (a // b, a % b)
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    // Check if either argument is BigInt or unknown (could be anytype)
    const left_type = self.inferExprScoped(args[0]) catch .unknown;
    const right_type = self.inferExprScoped(args[1]) catch .unknown;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    if (left_type == .bigint or right_type == .bigint or left_type == .unknown or right_type == .unknown) {
        // BigInt or unknown type - use runtime.bigIntDivmod
        try emitConst(self, "runtime.bigIntDivmod(");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, ", ");
        try emitConst(self, alloc_name);
        try emitConst(self, ")");
    } else {
        // Generate: .{ @divFloor(a, b), @mod(a, b) }
        try emitConst(self, ".{ @divFloor(");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, "), @mod(");
        try self.genExpr(args[0]);
        try emitConst(self, ", ");
        try self.genExpr(args[1]);
        try emitConst(self, ") }");
    }
}

/// Generate code for hash(obj)
/// Returns integer hash of object
/// Two-Flow: always uses runtime.pyHash() which handles all types (including PyValue, tuples, etc.)
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self, "(error.TypeError)");
        return;
    }

    // Check the type of the argument to generate appropriate code
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    switch (arg_type) {
        .bool => {
            // For bools: 1 for True, 0 for False (fast path)
            try emitConst(self, "@as(i64, if (");
            try self.genExpr(args[0]);
            try emitConst(self, ") 1 else 0)");
        },
        .string => {
            // For strings: use std.hash.Wyhash (fast path)
            try emitConst(self, "@as(i64, @bitCast(std.hash.Wyhash.hash(0, ");
            try self.genExpr(args[0]);
            try emitConst(self, ")))");
        },
        else => {
            // For all other types (int, float, tuple, PyValue, unknown, etc.):
            // use runtime.pyHash which handles all types including tuples and PyValue
            try emitConst(self, "runtime.pyHash(");
            try self.genExpr(args[0]);
            try emitConst(self, ")");
        },
    }
}
