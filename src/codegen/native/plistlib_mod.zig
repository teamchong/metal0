/// Python plistlib module - Apple plist file handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "load", h.c(".{}") }, .{ "loads", h.c(".{}") }, .{ "dump", h.c("{}") }, .{ "dumps", h.c("\"\"") },
    .{ "UID", genUID }, .{ "FMT_XML", h.I32(1) }, .{ "FMT_BINARY", h.I32(2) },
    .{ "Dict", h.c(".{}") }, .{ "Data", genData }, .{ "InvalidFileException", h.err("InvalidFileException") },
    .{ "readPlist", h.c(".{}") }, .{ "writePlist", h.c("{}") }, .{ "readPlistFromBytes", h.c(".{}") }, .{ "writePlistToBytes", h.c("\"\"") },
});

fn genUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .data = data }; }"); }
    else try self.emit(".{ .data = @as(i64, 0) }");
}

fn genData(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
