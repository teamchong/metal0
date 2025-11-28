/// Python _elementtree module - Internal ElementTree support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _elementtree.Element(tag, attrib={}, **extra)
pub fn genElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const tag = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }");
    } else {
        try self.emit(".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }");
    }
}

/// Generate _elementtree.SubElement(parent, tag, attrib={}, **extra)
pub fn genSubElement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const tag = ");
        try self.genExpr(args[1]);
        try self.emit("; break :blk .{ .tag = tag, .attrib = .{}, .text = null, .tail = null }; }");
    } else {
        try self.emit(".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }");
    }
}

/// Generate _elementtree.TreeBuilder(element_factory=None, *, comment_factory=None, pi_factory=None, insert_comments=False, insert_pis=False)
pub fn genTreeBuilder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .element_factory = null, .data = &[_][]const u8{}, .elem = &[_]@TypeOf(.{}){}, .last = null }");
}

/// Generate _elementtree.XMLParser(*, target=None, encoding=None)
pub fn genXMLParser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .target = null, .parser = null }");
}

/// Generate _elementtree.ParseError exception
pub fn genParseError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ParseError");
}

/// Generate Element.append(subelement)
pub fn genAppend(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.extend(elements)
pub fn genExtend(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.insert(index, subelement)
pub fn genInsert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.remove(subelement)
pub fn genRemove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.clear()
pub fn genClear(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.get(key, default=None)
pub fn genGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Element.set(key, value)
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Element.keys()
pub fn genKeys(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate Element.items()
pub fn genItems(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { []const u8, []const u8 }{}");
}

/// Generate Element.iter(tag=None)
pub fn genIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate Element.itertext()
pub fn genItertext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate Element.find(path, namespaces=None)
pub fn genFind(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Element.findall(path, namespaces=None)
pub fn genFindall(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate Element.findtext(path, default=None, namespaces=None)
pub fn genFindtext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Element.makeelement(tag, attrib)
pub fn genMakeelement(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .tag = \"\", .attrib = .{}, .text = null, .tail = null }");
}
