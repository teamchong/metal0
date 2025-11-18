/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for abs(n)
/// Returns absolute value
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @abs(n) or if (n < 0) -n else n
    try self.output.appendSlice(self.allocator, "@abs(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Generate: @min(a, @min(b, c))
    try self.output.appendSlice(self.allocator, "@min(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // Generate: @max(a, @max(b, c))
    try self.output.appendSlice(self.allocator, "@max(");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(arg);
    }
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for round(n)
/// Rounds to nearest integer
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @round(n)
    try self.output.appendSlice(self.allocator, "@round(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for pow(base, exp)
/// Returns base^exp
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // Generate: std.math.pow(f64, base, exp)
    try self.output.appendSlice(self.allocator, "std.math.pow(f64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[1]);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: &[_]u8{@intCast(n)}
    try self.output.appendSlice(self.allocator, "&[_]u8{@intCast(");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, ")}");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    try self.output.appendSlice(self.allocator, "@as(i64, ");
    try self.genExpr(args[0]);
    try self.output.appendSlice(self.allocator, "[0])");
}
