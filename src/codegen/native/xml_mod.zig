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

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
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
            try emitConst(c, "const _src = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; const f = std.fs.cwd().openFile(_src, .{{}}) catch break :{s} {s}; defer f.close(); const content = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch break :{s} {s}; _ = content; break :{s} {s}", .{ label, element_tree_struct, label, element_tree_struct, label, element_tree_struct });
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
            try emitConst(c, "const e = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; var r: std.ArrayList(u8) = .{{}}; r.appendSlice(__global_allocator, \"<\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; r.appendSlice(__global_allocator, e.text) catch unreachable; r.appendSlice(__global_allocator, \"</\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; break :{s} r.items", .{label});
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
            try emitConst(c, "var p = ");
            try c.genExpr(a[0]);
            try emitConst(c, "; const t = ");
            try c.genExpr(a[1]);
            try emitFmtConst(c, "; var ch = Element{{ .tag = t }}; p.children.append(__global_allocator, &ch) catch unreachable; break :{s} ch", .{label});
        }
    }.emit);
}
