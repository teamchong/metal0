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

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(element_tree_struct); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_parse: {{ const _src = ", .{id}); try self.genExpr(args[0]);
    try self.output.writer(self.allocator).print("; const f = std.fs.cwd().openFile(_src, .{{}}) catch break :__m{d}_parse {s}; defer f.close(); const content = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch break :__m{d}_parse {s}; _ = content; break :__m{d}_parse {s}; }})", .{ id, element_tree_struct, id, element_tree_struct, id, element_tree_struct });
}

fn genTostring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_tos: {{ const e = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; var r: std.ArrayList(u8) = .{{}}; r.appendSlice(__global_allocator, \"<\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; r.appendSlice(__global_allocator, e.text) catch unreachable; r.appendSlice(__global_allocator, \"</\") catch unreachable; r.appendSlice(__global_allocator, e.tag) catch unreachable; r.appendSlice(__global_allocator, \">\") catch unreachable; break :__m{d}_tos r.items; }})", .{id});
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("Element{}"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_sub: {{ var p = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const t = "); try self.genExpr(args[1]);
    try self.emitFmt("; var c = Element{{ .tag = t }}; p.children.append(__global_allocator, &c) catch unreachable; break :__m{d}_sub c; }})", .{id});
}
