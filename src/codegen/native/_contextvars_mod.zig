/// Python _contextvars module - Internal contextvars support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

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

fn genContextVar(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write(".{ .name = \"\", .default = null }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("cvi", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const __v = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; break :{s} .{{ .name = __v, .default = null }}", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .var = null, .old_value = null, .used = false }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genCopyContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genGet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("null");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genSet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{ .var = null, .old_value = null, .used = false }");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genReset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genRun(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("null");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genCopy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(".{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
