/// Python xml module - XML processing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

const element_tree_struct = "struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } pub fn write(s: *@This(), f: []const u8) void { _ = s; _ = f; } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", genParse },
    .{ "fromstring", h.discard("Element{}") },
    .{ "tostring", genTostring },
    .{ "Element", h.wrap("Element{ .tag = ", " }", "Element{}") },
    .{ "SubElement", genSubElement },
    .{ "ElementTree", h.c(element_tree_struct) },
    .{ "Comment", h.c("Element{ .tag = \"!--\" }") }, .{ "ProcessingInstruction", h.c("Element{ .tag = \"?\" }") },
    .{ "QName", h.wrap("struct { text: []const u8 }{ .text = ", " }", "struct { text: []const u8 = \"\" }{}") },
    .{ "indent", h.c("{}") }, .{ "dump", h.c("{}") }, .{ "iselement", h.c("true") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, element_tree_struct);
        return;
    }
    try self.withInlineBlock("parse", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const _src = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; const f = std.fs.cwd().openFile(_src, .{{}}) catch break :{s} {s}; defer f.close(); const content = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch break :{s} {s}; _ = content; break :{s} {s}", .{ label, element_tree_struct, label, element_tree_struct, label, element_tree_struct });
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genTostring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("tos", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const e = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.writeFmt("; var r: std.ArrayList(u8) = .{{}}; r.appendSlice(__global_allocator, \"<\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; r.appendSlice(__global_allocator, e.text) catch unreachable; r.appendSlice(__global_allocator, \"</\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; break :{s} r.items", .{label});
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try emitConst(self, "Element{}");
        return;
    }
    try self.withInlineBlock("sub", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("var p = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const t = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; var ch = Element{{ .tag = t }}; p.children.append(__global_allocator, &ch) catch unreachable; break :{s} ch", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}
