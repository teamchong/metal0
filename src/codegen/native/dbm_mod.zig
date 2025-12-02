/// Python dbm module - Interfaces to Unix databases
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "error", genConst("error.DbmError") }, .{ "whichdb", genConst("@as(?[]const u8, \"dbm.dumb\")") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const path = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .path = path, .data = metal0_runtime.PyDict([]const u8, []const u8).init() }; }"); } else { try self.emit(".{ .path = \"\", .data = metal0_runtime.PyDict([]const u8, []const u8).init() }"); }
}
