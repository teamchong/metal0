/// Python xml module - XML processing
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

const element_tree_struct = "struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } pub fn write(s: *@This(), f: []const u8) void { _ = s; _ = f; } }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", genParse }, .{ "fromstring", h.discard("Element{}") }, .{ "tostring", genTostring },
    .{ "Element", genElement }, .{ "SubElement", genSubElement }, .{ "ElementTree", h.c(element_tree_struct) },
    .{ "Comment", h.c("Element{ .tag = \"!--\" }") }, .{ "ProcessingInstruction", h.c("Element{ .tag = \"?\" }") },
    .{ "QName", genQName }, .{ "indent", h.c("{}") }, .{ "dump", h.c("{}") }, .{ "iselement", h.c("true") },
});

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _src = "); try self.genExpr(args[0]);
    try self.emit("; const f = std.fs.cwd().openFile(_src, .{}) catch break :blk " ++ element_tree_struct ++ "; defer f.close(); _ = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch {}; break :blk " ++ element_tree_struct ++ "; }");
}


fn genTostring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const e = "); try self.genExpr(args[0]);
    try self.emit("; var r: std.ArrayList(u8) = .{}; r.appendSlice(__global_allocator, \"<\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {}; r.appendSlice(__global_allocator, \">\") catch {}; r.appendSlice(__global_allocator, e.text) catch {}; r.appendSlice(__global_allocator, \"</\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {}; r.appendSlice(__global_allocator, \">\") catch {}; break :blk r.items; }");
}

fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("Element{}"); return; }
    try self.emit("Element{ .tag = "); try self.genExpr(args[0]); try self.emit(" }");
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { var p = "); try self.genExpr(args[0]); try self.emit("; const t = "); try self.genExpr(args[1]);
    try self.emit("; var c = Element{ .tag = t }; p.children.append(__global_allocator, &c) catch {}; break :blk c; }");
}

fn genQName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { text: []const u8 = \"\" }{}"); return; }
    try self.emit("struct { text: []const u8 }{ .text = "); try self.genExpr(args[0]); try self.emit(" }");
}

pub const genElementStruct = h.c("const Element = struct { tag: []const u8 = \"\", text: []const u8 = \"\", tail: []const u8 = \"\", attrib: hashmap_helper.StringHashMap([]const u8) = .{}, children: std.ArrayList(*Element) = .{}, pub fn get(s: *@This(), k: []const u8, d: ?[]const u8) ?[]const u8 { return s.attrib.get(k) orelse d; } pub fn set(s: *@This(), k: []const u8, v: []const u8) void { s.attrib.put(k, v) catch {}; } pub fn find(s: *@This(), p: []const u8) ?*Element { for (s.children.items) |c| if (std.mem.eql(u8, c.tag, p)) return c; return null; } pub fn findall(s: *@This(), p: []const u8) []*Element { var r: std.ArrayList(*Element) = .{}; for (s.children.items) |c| if (std.mem.eql(u8, c.tag, p)) r.append(__global_allocator, c) catch {}; return r.items; } pub fn iter(s: *@This()) []*Element { return s.children.items; } pub fn append(s: *@This(), e: *Element) void { s.children.append(__global_allocator, e) catch {}; } pub fn remove(s: *@This(), e: *Element) void { _ = s; _ = e; } }");
