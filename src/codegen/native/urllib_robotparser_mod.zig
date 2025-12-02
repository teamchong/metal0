/// Python urllib.robotparser module - robots.txt parser
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "RobotFileParser", genRobotFileParser },
});

fn genRobotFileParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .url = url, .last_checked = @as(i64, 0) }; }");
    } else try self.emit(".{ .url = \"\", .last_checked = @as(i64, 0) }");
}
