/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for abs(n)
/// Returns absolute value
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @abs(n) or if (n < 0) -n else n
    try self.emit("@abs(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // Single argument - iterable case: min([1, 2, 3]) or min(some_sequence)
        // Use runtime function that handles any iterable
        try self.emit("runtime.builtins.minIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
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
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // Single argument - iterable case: max([1, 2, 3]) or max(some_sequence)
        // Use runtime function that handles any iterable
        try self.emit("runtime.builtins.maxIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
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

    if (args.len == 1) {
        // round(n) - round to nearest integer
        try self.emit("@round(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places
    // For ndigits=0, just use @round
    // Otherwise use: @round(n * 10^ndigits) / 10^ndigits
    try self.emit("round_blk: {\n");
    try self.emit("const _val = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("const _ndigits = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emit("if (_ndigits == 0) break :round_blk @round(_val);\n");
    try self.emit("const _factor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(_ndigits)));\n");
    try self.emit("break :round_blk @round(_val * _factor) / _factor;\n");
    try self.emit("}");
}

/// Generate code for pow(base, exp) or pow(base, exp, mod)
/// Returns base^exp or base^exp % mod (modular exponentiation)
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

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
        // Generate: std.math.pow(f64, base, exp)
        try self.emit("std.math.pow(f64, ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    }
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: &[_]u8{@intCast(n)}
    try self.emit("&[_]u8{@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")}");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    try self.emit("@as(i64, ");
    try self.genExpr(args[0]);
    try self.emit("[0])");
}

/// Generate code for divmod(a, b)
/// Returns tuple (a // b, a % b)
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: .{ @divFloor(a, b), @rem(a, b) }
    try self.emit(".{ @divFloor(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit("), @rem(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(") }");
}

/// Generate code for hash(obj)
/// Returns integer hash of object
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Check the type of the argument to generate appropriate code
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    switch (arg_type) {
        .int => {
            // For integers: hash is the value itself (Python behavior)
            try self.emit("@as(i64, ");
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
            // For floats: hash the bit representation
            try self.emit("@as(i64, @bitCast(@as(u64, @bitCast(");
            try self.genExpr(args[0]);
            try self.emit("))))");
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
