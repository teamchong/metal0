/// Python xml module - XML processing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genParse }, .{ "fromstring", genFromstring }, .{ "tostring", genTostring },
    .{ "Element", genElement }, .{ "SubElement", genSubElement }, .{ "ElementTree", genElementTree },
    .{ "Comment", genComment }, .{ "ProcessingInstruction", genPI }, .{ "QName", genQName },
    .{ "indent", genUnit }, .{ "dump", genUnit }, .{ "iselement", genTrue },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genComment(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "Element{ .tag = \"!--\" }"); }
fn genPI(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "Element{ .tag = \"?\" }"); }
fn genElementTree(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } pub fn write(s: *@This(), f: []const u8) void { _ = s; _ = f; } }{}"); }

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _src = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("const f = std.fs.cwd().openFile(_src, .{}) catch break :blk struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } }{};\n");
    try self.emitIndent(); try self.emit("defer f.close(); _ = f.readToEndAlloc(__global_allocator, 10*1024*1024) catch {};\n");
    try self.emitIndent(); try self.emit("break :blk struct { root: ?*Element = null, pub fn getroot(s: *@This()) ?*Element { return s.root; } }{}; }");
}

fn genFromstring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk Element{}; }");
}

fn genTostring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const e = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("var r: std.ArrayList(u8) = .{};\n");
    try self.emitIndent(); try self.emit("r.appendSlice(__global_allocator, \"<\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {};\n");
    try self.emitIndent(); try self.emit("r.appendSlice(__global_allocator, \">\") catch {}; r.appendSlice(__global_allocator, e.text) catch {};\n");
    try self.emitIndent(); try self.emit("r.appendSlice(__global_allocator, \"</\") catch {}; r.appendSlice(__global_allocator, e.tag) catch {};\n");
    try self.emitIndent(); try self.emit("r.appendSlice(__global_allocator, \">\") catch {}; break :blk r.items; }");
}

fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("Element{}"); return; }
    try self.emit("Element{ .tag = "); try self.genExpr(args[0]); try self.emit(" }");
}

fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { var p = "); try self.genExpr(args[0]); try self.emit("; const t = "); try self.genExpr(args[1]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("var c = Element{ .tag = t }; p.children.append(__global_allocator, &c) catch {}; break :blk c; }");
}

fn genQName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { text: []const u8 = \"\" }{}"); return; }
    try self.emit("struct { text: []const u8 }{ .text = "); try self.genExpr(args[0]); try self.emit(" }");
}

pub fn genElementStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genConst(self, args, "const Element = struct { tag: []const u8 = \"\", text: []const u8 = \"\", tail: []const u8 = \"\", attrib: hashmap_helper.StringHashMap([]const u8) = .{}, children: std.ArrayList(*Element) = .{}, pub fn get(s: *@This(), k: []const u8, d: ?[]const u8) ?[]const u8 { return s.attrib.get(k) orelse d; } pub fn set(s: *@This(), k: []const u8, v: []const u8) void { s.attrib.put(k, v) catch {}; } pub fn find(s: *@This(), p: []const u8) ?*Element { for (s.children.items) |c| if (std.mem.eql(u8, c.tag, p)) return c; return null; } pub fn findall(s: *@This(), p: []const u8) []*Element { var r: std.ArrayList(*Element) = .{}; for (s.children.items) |c| if (std.mem.eql(u8, c.tag, p)) r.append(__global_allocator, c) catch {}; return r.items; } pub fn iter(s: *@This()) []*Element { return s.children.items; } pub fn append(s: *@This(), e: *Element) void { s.children.append(__global_allocator, e) catch {}; } pub fn remove(s: *@This(), e: *Element) void { _ = s; _ = e; } }");
}
