/// Python _contextvars module - Internal contextvars support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "context_var", genContextVar },
    .{ "context", genContext },
    .{ "token", genToken },
    .{ "copy_context", genCopyContext },
    .{ "get", genGet },
    .{ "set", genSet },
    .{ "reset", genReset },
    .{ "run", genRun },
    .{ "copy", genCopy },
});

fn genContextVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit(".{ .name = \"\", .default = null }");
        return;
    }
    try self.withInlineBlock("cvi", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const __v = ");
            try c.genExpr(a[0]);
            try c.emitFmt("; break :{s} .{{ .name = __v, .default = null }}", .{label});
        }
    }.emit);
}

fn genContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(".{}");
}

fn genToken(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(".{ .var = null, .old_value = null, .used = false }");
}

fn genCopyContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(".{}");
}

fn genGet(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("null");
}

fn genSet(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(".{ .var = null, .old_value = null, .used = false }");
}

fn genReset(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("{}");
}

fn genRun(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit("null");
}

fn genCopy(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try self.emit(".{}");
}
