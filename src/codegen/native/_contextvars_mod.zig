/// Python _contextvars module - Internal contextvars support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "context_var", genContextVar }, .{ "context", genEmpty }, .{ "token", genToken },
    .{ "copy_context", genEmpty }, .{ "get", genNull }, .{ "set", genToken },
    .{ "reset", genUnit }, .{ "run", genNull }, .{ "copy", genEmpty },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genToken(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .var = null, .old_value = null, .used = false }"); }

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .default = null }; }"); } else { try self.emit(".{ .name = \"\", .default = null }"); }
}
