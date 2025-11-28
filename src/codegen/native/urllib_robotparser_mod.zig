/// Python urllib.robotparser module - robots.txt parser
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate urllib.robotparser.RobotFileParser class
pub fn genRobotFileParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const url = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .url = url, .last_checked = @as(i64, 0) }; }");
    } else {
        try self.emit(".{ .url = \"\", .last_checked = @as(i64, 0) }");
    }
}
