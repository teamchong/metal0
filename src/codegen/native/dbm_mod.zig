/// Python dbm module - Interfaces to Unix databases
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen }, .{ "error", h.err("DbmError") }, .{ "whichdb", h.c("@as(?[]const u8, \"dbm.dumb\")") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .path = path, .data = metal0_runtime.PyDict([]const u8, []const u8).init() }; }"); } else { try self.emit(".{ .path = \"\", .data = metal0_runtime.PyDict([]const u8, []const u8).init() }"); }
}
