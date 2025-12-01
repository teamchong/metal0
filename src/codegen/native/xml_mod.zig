/// Python xml module - XML processing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genParse },
    .{ "fromstring", genFromstring },
    .{ "tostring", genTostring },
    .{ "Element", genElement },
    .{ "SubElement", genSubElement },
    .{ "ElementTree", genElementTree },
    .{ "Comment", genComment },
    .{ "ProcessingInstruction", genProcessingInstruction },
    .{ "QName", genQName },
    .{ "indent", genIndent },
    .{ "dump", genDump },
    .{ "iselement", genIselement },
});

/// Generate xml.etree.ElementTree.parse(source) -> ElementTree
pub fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("xml_parse_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _source = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const file = std.fs.cwd().openFile(_source, .{}) catch break :xml_parse_blk struct { root: ?*Element = null, pub fn getroot(self: *@This()) ?*Element { return self.root; } }{};\n");
    try self.emitIndent();
    try self.emit("defer file.close();\n");
    try self.emitIndent();
    try self.emit("const content = file.readToEndAlloc(__global_allocator, 10 * 1024 * 1024) catch break :xml_parse_blk struct { root: ?*Element = null, pub fn getroot(self: *@This()) ?*Element { return self.root; } }{};\n");
    try self.emitIndent();
    try self.emit("_ = content;\n");
    try self.emitIndent();
    try self.emit("break :xml_parse_blk struct { root: ?*Element = null, pub fn getroot(self: *@This()) ?*Element { return self.root; } }{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate xml.etree.ElementTree.fromstring(text) -> Element
pub fn genFromstring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("xml_fromstring_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _text = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _text;\n");
    try self.emitIndent();
    try self.emit("break :xml_fromstring_blk Element{};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate xml.etree.ElementTree.tostring(element) -> bytes
pub fn genTostring(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("xml_tostring_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _elem = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \"<\") catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _elem.tag) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \">\") catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _elem.text) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \"</\") catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, _elem.tag) catch {};\n");
    try self.emitIndent();
    try self.emit("_result.appendSlice(__global_allocator, \">\") catch {};\n");
    try self.emitIndent();
    try self.emit("break :xml_tostring_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate xml.etree.ElementTree.Element(tag, attrib={}) -> Element
pub fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("Element{}");
        return;
    }

    try self.emit("Element{ .tag = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

/// Generate xml.etree.ElementTree.SubElement(parent, tag, attrib={}) -> Element
pub fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("xml_subelement_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _parent = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _tag = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _child = Element{ .tag = _tag };\n");
    try self.emitIndent();
    try self.emit("_parent.children.append(__global_allocator, &_child) catch {};\n");
    try self.emitIndent();
    try self.emit("break :xml_subelement_blk _child;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate xml.etree.ElementTree.ElementTree(element=None) -> ElementTree
pub fn genElementTree(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("root: ?*Element = null,\n");
    try self.emitIndent();
    try self.emit("pub fn getroot(self: *@This()) ?*Element { return self.root; }\n");
    try self.emitIndent();
    try self.emit("pub fn write(self: *@This(), file: []const u8) void { _ = self; _ = file; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate xml.etree.ElementTree.Comment(text=None) -> Comment element
pub fn genComment(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("Element{ .tag = \"!--\" }");
}

/// Generate xml.etree.ElementTree.ProcessingInstruction(target, text=None) -> PI element
pub fn genProcessingInstruction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("Element{ .tag = \"?\" }");
}

/// Generate xml.etree.ElementTree.QName(text_or_uri, tag=None) -> QName
pub fn genQName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { text: []const u8 = \"\" }{}");
        return;
    }
    try self.emit("struct { text: []const u8 }{ .text = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}

/// Generate xml.etree.ElementTree.indent(tree, space="  ", level=0) -> None
pub fn genIndent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate xml.etree.ElementTree.dump(elem) -> None (debug output)
pub fn genDump(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate xml.etree.ElementTree.iselement(element) -> bool
pub fn genIselement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Element struct definition (referenced in generated code)
pub fn genElementStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("const Element = struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("tag: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("text: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("tail: []const u8 = \"\",\n");
    try self.emitIndent();
    try self.emit("attrib: hashmap_helper.StringHashMap([]const u8) = .{},\n");
    try self.emitIndent();
    try self.emit("children: std.ArrayList(*Element) = .{},\n");
    try self.emitIndent();
    try self.emit("pub fn get(self: *@This(), key: []const u8, default: ?[]const u8) ?[]const u8 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("return self.attrib.get(key) orelse default;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn set(self: *@This(), key: []const u8, value: []const u8) void {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("self.attrib.put(key, value) catch {};\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn find(self: *@This(), path: []const u8) ?*Element {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("for (self.children.items) |child| if (std.mem.eql(u8, child.tag, path)) return child;\n");
    try self.emitIndent();
    try self.emit("return null;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn findall(self: *@This(), path: []const u8) []*Element {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var result: std.ArrayList(*Element) = .{};\n");
    try self.emitIndent();
    try self.emit("for (self.children.items) |child| if (std.mem.eql(u8, child.tag, path)) result.append(__global_allocator, child) catch {};\n");
    try self.emitIndent();
    try self.emit("return result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn iter(self: *@This()) []*Element { return self.children.items; }\n");
    try self.emitIndent();
    try self.emit("pub fn append(self: *@This(), elem: *Element) void { self.children.append(__global_allocator, elem) catch {}; }\n");
    try self.emitIndent();
    try self.emit("pub fn remove(self: *@This(), elem: *Element) void { _ = self; _ = elem; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
