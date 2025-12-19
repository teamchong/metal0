/// Python _contextvars module - Internal contextvars support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
        try emitConst(self, ".{ .name = \"\", .default = null }");
        return;
    }
    try self.withInlineBlock("cvi", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const __v = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} .{{ .name = __v, .default = null }}", .{label});
        }
    }.emit);
}

fn genContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{}");
}

fn genToken(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{ .var = null, .old_value = null, .used = false }");
}

fn genCopyContext(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{}");
}

fn genGet(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "null");
}

fn genSet(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{ .var = null, .old_value = null, .used = false }");
}

fn genReset(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "{}");
}

fn genRun(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "null");
}

fn genCopy(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, ".{}");
}
