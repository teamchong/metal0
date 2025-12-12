/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const type_traits = @import("../../../analysis/traits/type_traits.zig");

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
fn isExprUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr == .name) {
        const name = expr.name.id;
        // Check if variable type is PyValue or unknown
        if (self.type_inferrer.var_types.get(name)) |var_type| {
            switch (var_type) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        // Fall back to confidence check
        return self.isVarUncertain(name);
    }
    return false;
}

/// Generate code for abs(n)
/// Returns absolute value
/// Two-Flow: routes uncertain operands to PyValue.pyAbs()
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // abs() requires exactly one argument - generate an error union for assertRaises
        try self.emit("(error.TypeError)");
        return;
    }

    // Two-Flow: Check if argument is uncertain
    if (isExprUncertain(self, args[0])) {
        // Route to PyValue.pyAbs() for runtime type safety
        try self.genExpr(args[0]);
        try self.emit(".pyAbs()");
        return;
    }

    // Check if arg is a bool - need to cast to int first since @abs doesn't work on bool
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isBoolean(arg_type)) {
        // abs(True) = 1, abs(False) = 0
        // Just convert bool to int: @intFromBool(...)
        try self.emit("@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Generate: @abs(n)
    try self.emit("@abs(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
/// Two-Flow: routes uncertain operands to PyValue.pyMin()
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: min([1, 2, 3]) or min(some_sequence)
        // Use runtime function that handles any iterable
        try self.emit("runtime.builtins.minIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
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
            try self.emit(".pyMin(");
            try self.genExpr(arg);
            try self.emit(")");
        }
        return;
    }

    // Generate: @min(a, @min(b, c))
    try self.emit("@min(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit(")");
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
/// Two-Flow: routes uncertain operands to PyValue.pyMax()
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: max([1, 2, 3]) or max(some_sequence)
        // Use runtime function that handles any iterable
        try self.emit("runtime.builtins.maxIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
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
            try self.emit(".pyMax(");
            try self.genExpr(arg);
            try self.emit(")");
        }
        return;
    }

    // Generate: @max(a, @max(b, c))
    try self.emit("@max(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit(")");
}

/// Generate code for round(n) or round(n, ndigits)
/// Rounds to nearest integer or specified decimal places
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    // round(n) or round(n, None) - round to nearest integer
    if (args.len == 1 or (args.len == 2 and isNoneArg(args[1]))) {
        // Use runtime.builtins.pyRound to handle both int and float
        try self.emit("runtime.builtins.pyRound(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places
    // For ndigits=0, just use @round
    // Otherwise use: @round(n * 10^ndigits) / 10^ndigits
    // Use runtime round function to handle both int and float values
    try self.emit("(try runtime.builtins.round(");
    try self.genExpr(args[0]);
    try self.emit(", .{");
    try self.genExpr(args[1]);
    try self.emit("}))");
}

/// Generate code for pow(base, exp) or pow(base, exp, mod)
/// Returns base^exp or base^exp % mod (modular exponentiation)
/// Uses runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 3) {
        // pow(base, exp, mod) - modular exponentiation
        // Generate: @rem(@as(i64, @intFromFloat(std.math.pow(f64, base, exp))), mod)
        try self.emit("@rem(@as(i64, @intFromFloat(std.math.pow(f64, @as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(f64, @floatFromInt(");
        try self.genExpr(args[1]);
        try self.emit("))))), ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        // pow(base, exp) - standard power
        // Use runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
        // Generate: (try runtime.builtins.pow.call(base, exp))
        try self.emit("(try runtime.builtins.pow.call(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit("))");
    }
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Generate: &[_]u8{@intCast(n)}
    try self.emit("&[_]u8{@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")}");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    // Need extra parens when arg is a slice subscript (generates labeled block)
    const needs_parens = args[0] == .subscript and args[0].subscript.slice == .slice;
    try self.emit("@as(i64, ");
    if (needs_parens) try self.emit("(");
    try self.genExpr(args[0]);
    if (needs_parens) try self.emit(")");
    try self.emit("[0])");
}

/// Generate code for divmod(a, b)
/// Returns tuple (a // b, a % b)
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Check if either argument is BigInt or unknown (could be anytype)
    const left_type = self.inferExprScoped(args[0]) catch .unknown;
    const right_type = self.inferExprScoped(args[1]) catch .unknown;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    if (left_type == .bigint or right_type == .bigint or left_type == .unknown or right_type == .unknown) {
        // BigInt or unknown type - use runtime.bigIntDivmod
        try self.emit("runtime.bigIntDivmod(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(")");
    } else {
        // Generate: .{ @divFloor(a, b), @mod(a, b) }
        try self.emit(".{ @divFloor(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit("), @mod(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(") }");
    }
}

/// Generate code for hash(obj)
/// Returns integer hash of object
/// Two-Flow: routes uncertain operands to PyValue.pyHash()
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Two-Flow: Check if argument is uncertain
    if (isExprUncertain(self, args[0])) {
        // Route to PyValue.pyHash() for runtime type safety
        try self.genExpr(args[0]);
        try self.emit(".pyHash()");
        return;
    }

    // Check the type of the argument to generate appropriate code
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // float() now always returns f64 (uses catch 0.0 internally), not error union

    switch (arg_type) {
        .int => {
            // For integers: use runtime.pyHash to handle both i64 and IntResult (from int(large_float))
            try self.emit("runtime.pyHash(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
        .bool => {
            // For bools: 1 for True, 0 for False
            try self.emit("@as(i64, if (");
            try self.genExpr(args[0]);
            try self.emit(") 1 else 0)");
        },
        .float => {
            // For floats: use Python's float hash algorithm (from runtime.pyHash)
            try self.emit("runtime.pyHash(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
        .string => {
            // For strings: use std.hash.Wyhash
            try self.emit("@as(i64, @bitCast(std.hash.Wyhash.hash(0, ");
            try self.genExpr(args[0]);
            try self.emit(")))");
        },
        else => {
            // For other types: use runtime.pyHash which handles PyObject
            try self.emit("runtime.pyHash(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
    }
}
