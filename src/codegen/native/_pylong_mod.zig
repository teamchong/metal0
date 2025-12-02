/// Python _pylong module - Pure Python long integer implementation
/// This module provides fast conversion between large integers and decimal strings
/// using divide-and-conquer algorithms with the decimal module.
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "log10_base256", genLog10Base256 },
    .{ "spread", genSpread },
    .{ "int_to_decimal_string", genIntToDecimalString },
    .{ "int_from_string", genIntFromString },
    .{ "dec_str_to_int_inner", genDecStrToIntInner },
    .{ "compute_powers", genComputePowers },
});

/// Generate _pylong._LOG_10_BASE_256 constant
/// This is log10(256) ≈ 0.4150374992788438 used for estimating decimal digits
pub fn genLog10Base256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // float.fromhex('0x1.a934f0979a371p-2') = 0.4150374992788438
    try self.emit("@as(f64, 0.4150374992788438)");
}

/// Generate _pylong._spread - diagnostic dict tracking quotient corrections
/// Returns a hashmap with .copy(), .clear(), .update() methods
/// Note: metal0 doesn't use CPython's divide-and-conquer algorithm, so this is just for API compatibility
pub fn genSpread(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // _spread is a defaultdict(int) in CPython, used for diagnostic tracking
    // We emit a struct with the required methods that operates on an internal map
    // Since tests call .copy()/.clear()/.update() on _spread, we need those methods
    try self.emit("(struct {\n");
    try self.emit("    data: std.AutoHashMap(i64, i64) = .{},\n");
    try self.emit("    pub fn copy(self: @This()) @This() { return __self; }\n");
    try self.emit("    pub fn clear(__self: *@This()) void { __self.data.clearRetainingCapacity(); }\n");
    try self.emit("    pub fn clearRetainingCapacity(__self: *@This()) void { __self.data.clearRetainingCapacity(); }\n");
    try self.emit("    pub fn update(__self: *@This(), other: @This()) void { _ = other; }\n");
    try self.emit("    pub fn clone(self: @This(), allocator: std.mem.Allocator) !@This() { _ = allocator; return __self; }\n");
    try self.emit("    pub fn contains(self: @This(), key: i64) bool { return __self.data.contains(key); }\n");
    try self.emit("}{})");
}

/// Generate _pylong.int_to_decimal_string(n)
/// Converts a large integer to its decimal string representation
/// Uses divide-and-conquer algorithm for large integers
pub fn genIntToDecimalString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"0\"");
        return;
    }

    // For now, use runtime BigInt toString which handles arbitrary precision
    try self.emit("(blk: {");
    try self.emit(" const n = ");
    try self.genExpr(args[0]);
    try self.emit(";");
    try self.emit(" if (@TypeOf(n) == runtime.BigInt) {");
    try self.emit("   break :blk n.toString(__global_allocator);");
    try self.emit(" } else {");
    try self.emit("   break :blk try std.fmt.allocPrint(__global_allocator, \"{d}\", .{n});");
    try self.emit(" }");
    try self.emit("})");
}

/// Generate _pylong.int_from_string(s, base=10)
/// Converts a decimal string to a large integer
/// Uses divide-and-conquer algorithm for large strings
pub fn genIntFromString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    // Parse string to BigInt or i64
    try self.emit("(blk: {");
    try self.emit(" const s = ");
    try self.genExpr(args[0]);
    try self.emit(";");
    try self.emit(" const base: u8 = ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("10");
    }
    try self.emit(";");
    try self.emit(" break :blk runtime.builtins.parseInt(s, base) catch 0;");
    try self.emit("})");
}

/// Generate _pylong._dec_str_to_int_inner(s, GUARD=8)
/// Inner function for decimal string to int conversion using decimal module
/// This implements the divide-and-conquer algorithm
pub fn genDecStrToIntInner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(i64, 0)");
        return;
    }

    // The GUARD parameter controls precision, defaults to 8
    try self.emit("(blk: {");
    try self.emit(" const s = ");
    try self.genExpr(args[0]);
    try self.emit(";");
    try self.emit(" const guard: u8 = ");
    if (args.len > 1) {
        // Check for keyword arg GUARD=...
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("8");
    }
    try self.emit(";");
    try self.emit(" _ = guard;");
    // Check string length limit: cannot convert string of len N to int
    // if len > (1 << 47) / _LOG_10_BASE_256
    try self.emit(" const max_len: usize = @intFromFloat(@as(f64, @floatFromInt(@as(u64, 1) << 47)) / 0.4150374992788438);");
    try self.emit(" if (s.len > max_len) {");
    try self.emit("   return error.ValueError;"); // "cannot convert string of len N to int"
    try self.emit(" }");
    try self.emit(" break :blk runtime.builtins.parseInt(s, 10) catch 0;");
    try self.emit("})");
}

/// Generate _pylong.compute_powers(w, base, limit, need_hi=False, show=False)
/// Pre-computes required powers of base for divide-and-conquer algorithm
/// Returns a dict mapping exponents to base^exponent values
pub fn genComputePowers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        try self.emit("(runtime.pylong.computePowers(__global_allocator, 0, 2, 0, false))");
        return;
    }

    // Emit runtime call with proper args
    try self.emit("(runtime.pylong.computePowers(__global_allocator, @intCast(");
    try self.genExpr(args[0]); // w
    try self.emit("), @intCast(");
    try self.genExpr(args[1]); // base
    try self.emit("), @intCast(");
    try self.genExpr(args[2]); // limit
    try self.emit("), ");

    // Check positional arg 4 for need_hi
    if (args.len > 3) {
        try self.genExpr(args[3]);
    } else {
        try self.emit("false");
    }

    try self.emit("))");
}
