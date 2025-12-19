/// Python _collections module - C accelerator for collections (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "deque", genDeque },
    .{ "_deque_iterator", genDequeIterator },
    .{ "_deque_reverse_iterator", genDequeReverseIterator },
    .{ "_count_elements", genCountElements },
});

fn genDeque(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("deque", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("var d = std.ArrayListUnmanaged(@TypeOf(");
                const output1 = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.write("[0])).init(__global_allocator); d.appendSlice(");
                    const output2 = b2.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
                try c.genExpr(a[0]);
                {
                    const b3 = try c.getBuilder();
                    try b3.writeFmt(") catch unreachable; break :{s} .{{ .items = d.items, .maxlen = null }}", .{label});
                    const output3 = b3.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output3);
                }
            }
        }.emit);
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genDequeIterator(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("diter", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("const d = ");
                const output1 = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.writeFmt("; break :{s} .{{ .deque = d, .index = 0 }}", .{label});
                    const output2 = b2.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
            }
        }.emit);
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .deque = null, .index = 0 }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genDequeReverseIterator(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.withInlineBlock("driter", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("const d = ");
                const output1 = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.writeFmt("; break :{s} .{{ .deque = d, .index = d.items.len }}", .{label});
                    const output2 = b2.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
            }
        }.emit);
    } else {
        const b = try self.getBuilder();
        try b.write(".{ .deque = null, .index = 0 }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

fn genCountElements(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write("{}");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
