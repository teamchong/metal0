/// Python xml.sax module - SAX XML parsing
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate xml.sax.make_parser(parser_list=[])
pub fn genMake_parser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate xml.sax.parse(source, handler, errorHandler=handler.ErrorHandler())
pub fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate xml.sax.parseString(string, handler, errorHandler=handler.ErrorHandler())
pub fn genParseString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Handler base classes
// ============================================================================

/// Generate xml.sax.ContentHandler
pub fn genContentHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate xml.sax.DTDHandler
pub fn genDTDHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate xml.sax.EntityResolver
pub fn genEntityResolver(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate xml.sax.ErrorHandler
pub fn genErrorHandler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

// ============================================================================
// InputSource class
// ============================================================================

/// Generate xml.sax.xmlreader.InputSource
pub fn genInputSource(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const system_id = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }; }");
    } else {
        try self.emit(".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }");
    }
}

/// Generate xml.sax.xmlreader.AttributesImpl
pub fn genAttributesImpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .attrs = .{} }");
}

/// Generate xml.sax.xmlreader.AttributesNSImpl
pub fn genAttributesNSImpl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .attrs = .{}, .qnames = .{} }");
}

// ============================================================================
// Exceptions
// ============================================================================

pub fn genSAXException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SAXException");
}

pub fn genSAXNotRecognizedException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SAXNotRecognizedException");
}

pub fn genSAXNotSupportedException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SAXNotSupportedException");
}

pub fn genSAXParseException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SAXParseException");
}
