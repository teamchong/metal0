/// Python _collections module - C accelerator for collections (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
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
    .{ "deque", genDeque },
    .{ "_deque_iterator", genDequeIterator },
    .{ "_deque_reverse_iterator", genDequeReverseIterator },
    .{ "_count_elements", genCountElements },
});

fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("deque", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "var d = std.ArrayListUnmanaged(@TypeOf(");
                try c.genExpr(a[0]);
                try emitConst(c, "[0])).init(__global_allocator); d.appendSlice(");
                try c.genExpr(a[0]);
                try emitFmtConst(c, ") catch unreachable; break :{s} .{{ .items = d.items, .maxlen = null }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .items = &[_]@TypeOf(0){}, .maxlen = null }");
    }
}

fn genDequeIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("diter", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const d = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; break :{s} .{{ .deque = d, .index = 0 }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .deque = null, .index = 0 }");
    }
}

fn genDequeReverseIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("driter", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const d = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; break :{s} .{{ .deque = d, .index = d.items.len }}", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, ".{ .deque = null, .index = 0 }");
    }
}

fn genCountElements(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    try emitConst(self, "{}");
}
