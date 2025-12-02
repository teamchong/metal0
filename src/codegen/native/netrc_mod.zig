/// Python netrc module - netrc file parsing
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "netrc", genNetrc },
    .{ "NetrcParseError", h.err("NetrcParseError") },
});

fn genNetrc(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const file = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .file = file, .hosts = .{}, .macros = .{} }; }");
    } else {
        try self.emit(".{ .file = @as(?[]const u8, null), .hosts = .{}, .macros = .{} }");
    }
}
