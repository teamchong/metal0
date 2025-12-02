/// Python pyexpat module - Fast XML parsing using Expat
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genExpatErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.ExpatError"); }
fn genTypeMarker(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@TypeOf(.{})"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ParserCreate", genParserCreate }, .{ "Parse", genI32_1 }, .{ "ParseFile", genI32_1 },
    .{ "SetBase", genUnit }, .{ "GetBase", genEmptyStr }, .{ "GetInputContext", genEmptyStr },
    .{ "ExternalEntityParserCreate", genEmpty }, .{ "SetParamEntityParsing", genI32_1 }, .{ "UseForeignDTD", genUnit },
    .{ "ErrorString", genErrorString }, .{ "XMLParserType", genTypeMarker }, .{ "ExpatError", genExpatErr }, .{ "error", genExpatErr },
    .{ "XML_PARAM_ENTITY_PARSING_NEVER", genI32_0 }, .{ "XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE", genI32_1 },
    .{ "XML_PARAM_ENTITY_PARSING_ALWAYS", genI32_2 },
    .{ "version_info", genVersionInfo }, .{ "EXPAT_VERSION", genExpatVersion }, .{ "native_encoding", genNativeEncoding },
    .{ "features", genFeatures }, .{ "model", genModel }, .{ "errors", genErrors },
});

fn genParserCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .buffer_text = false, .buffer_size = 8192, .buffer_used = 0, .ordered_attributes = false, .specified_attributes = false, .returns_unicode = true }"); }
fn genErrorString(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"unknown error\""); }
fn genVersionInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 2), @as(i32, 5), @as(i32, 0) }"); }
fn genExpatVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"expat_2.5.0\""); }
fn genNativeEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"UTF-8\""); }
fn genFeatures(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]struct { []const u8, i32 }{ .{ \"sizeof(XML_Char)\", 1 }, .{ \"sizeof(XML_LChar)\", 1 } }"); }
fn genModel(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .XML_CTYPE_EMPTY = 1, .XML_CTYPE_ANY = 2, .XML_CTYPE_MIXED = 3, .XML_CTYPE_NAME = 4, .XML_CTYPE_CHOICE = 5, .XML_CTYPE_SEQ = 6, .XML_CQUANT_NONE = 0, .XML_CQUANT_OPT = 1, .XML_CQUANT_REP = 2, .XML_CQUANT_PLUS = 3 }"); }
fn genErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .XML_ERROR_NO_MEMORY = \"out of memory\", .XML_ERROR_SYNTAX = \"syntax error\", .XML_ERROR_NO_ELEMENTS = \"no element found\", .XML_ERROR_INVALID_TOKEN = \"not well-formed (invalid token)\" }"); }
