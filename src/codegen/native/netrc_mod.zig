/// Python netrc module - netrc file parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate netrc.netrc(file=None)
pub fn genNetrc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const file = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = file, .hosts = .{}, .macros = .{} }; }");
    } else {
        try self.emit(".{ .file = @as(?[]const u8, null), .hosts = .{}, .macros = .{} }");
    }
}

// ============================================================================
// Exception
// ============================================================================

pub fn genNetrcParseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NetrcParseError");
}
