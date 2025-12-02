/// Python contextvars module - Context Variables
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ContextVar", genContextVar }, .{ "Token", genToken }, .{ "Context", genContext }, .{ "copy_context", genContext },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .var = null, .old_value = null }"); }
fn genContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = metal0_runtime.PyDict([]const u8, ?anyopaque).init() }"); }

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .value = null }; }"); } else try self.emit(".{ .name = \"\", .value = null }");
}
