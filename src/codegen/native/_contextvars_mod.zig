/// Python _contextvars module - Internal contextvars support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "context_var", genContextVar }, .{ "context", genConst(".{}") }, .{ "token", genConst(".{ .var = null, .old_value = null, .used = false }") },
    .{ "copy_context", genConst(".{}") }, .{ "get", genConst("null") }, .{ "set", genConst(".{ .var = null, .old_value = null, .used = false }") },
    .{ "reset", genConst("{}") }, .{ "run", genConst("null") }, .{ "copy", genConst(".{}") },
});

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const name = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .name = name, .default = null }; }"); } else { try self.emit(".{ .name = \"\", .default = null }"); }
}
