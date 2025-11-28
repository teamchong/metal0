/// Python pyexpat module - Fast XML parsing using Expat
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pyexpat.ParserCreate(encoding=None, namespace_separator=None)
pub fn genParserCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .buffer_text = false, .buffer_size = 8192, .buffer_used = 0, .ordered_attributes = false, .specified_attributes = false, .returns_unicode = true }");
}

/// Generate parser.Parse(data, isfinal=False)
pub fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate parser.ParseFile(file)
pub fn genParseFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate parser.SetBase(base)
pub fn genSetBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate parser.GetBase()
pub fn genGetBase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate parser.GetInputContext()
pub fn genGetInputContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate parser.ExternalEntityParserCreate(context, encoding=None)
pub fn genExternalEntityParserCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate parser.SetParamEntityParsing(flag)
pub fn genSetParamEntityParsing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate parser.UseForeignDTD(flag=True)
pub fn genUseForeignDTD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate pyexpat.ErrorString(errno)
pub fn genErrorString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"unknown error\"");
}

/// Generate pyexpat.XMLParserType type
pub fn genXMLParserType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@TypeOf(.{})");
}

/// Generate pyexpat.ExpatError exception
pub fn genExpatError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ExpatError");
}

/// Generate pyexpat.error exception (alias)
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ExpatError");
}

/// Generate pyexpat.XML_PARAM_ENTITY_PARSING_NEVER constant
pub fn genXmlParamEntityParsingNever(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate pyexpat.XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE constant
pub fn genXmlParamEntityParsingUnlessStandalone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate pyexpat.XML_PARAM_ENTITY_PARSING_ALWAYS constant
pub fn genXmlParamEntityParsingAlways(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate pyexpat.version_info tuple
pub fn genVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 2), @as(i32, 5), @as(i32, 0) }");
}

/// Generate pyexpat.EXPAT_VERSION constant
pub fn genExpatVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"expat_2.5.0\"");
}

/// Generate pyexpat.native_encoding constant
pub fn genNativeEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"UTF-8\"");
}

/// Generate pyexpat.features list
pub fn genFeatures(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { []const u8, i32 }{ .{ \"sizeof(XML_Char)\", 1 }, .{ \"sizeof(XML_LChar)\", 1 } }");
}

/// Generate pyexpat.model dict
pub fn genModel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .XML_CTYPE_EMPTY = 1, .XML_CTYPE_ANY = 2, .XML_CTYPE_MIXED = 3, .XML_CTYPE_NAME = 4, .XML_CTYPE_CHOICE = 5, .XML_CTYPE_SEQ = 6, .XML_CQUANT_NONE = 0, .XML_CQUANT_OPT = 1, .XML_CQUANT_REP = 2, .XML_CQUANT_PLUS = 3 }");
}

/// Generate pyexpat.errors module
pub fn genErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .XML_ERROR_NO_MEMORY = \"out of memory\", .XML_ERROR_SYNTAX = \"syntax error\", .XML_ERROR_NO_ELEMENTS = \"no element found\", .XML_ERROR_INVALID_TOKEN = \"not well-formed (invalid token)\" }");
}
