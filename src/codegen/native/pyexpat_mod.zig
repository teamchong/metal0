/// Python pyexpat module - Fast XML parsing using Expat
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ParserCreate", genConst(".{ .buffer_text = false, .buffer_size = 8192, .buffer_used = 0, .ordered_attributes = false, .specified_attributes = false, .returns_unicode = true }") },
    .{ "Parse", genConst("@as(i32, 1)") }, .{ "ParseFile", genConst("@as(i32, 1)") },
    .{ "SetBase", genConst("{}") }, .{ "GetBase", genConst("\"\"") }, .{ "GetInputContext", genConst("\"\"") },
    .{ "ExternalEntityParserCreate", genConst(".{}") }, .{ "SetParamEntityParsing", genConst("@as(i32, 1)") }, .{ "UseForeignDTD", genConst("{}") },
    .{ "ErrorString", genConst("\"unknown error\"") }, .{ "XMLParserType", genConst("@TypeOf(.{})") },
    .{ "ExpatError", genConst("error.ExpatError") }, .{ "error", genConst("error.ExpatError") },
    .{ "XML_PARAM_ENTITY_PARSING_NEVER", genConst("@as(i32, 0)") },
    .{ "XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE", genConst("@as(i32, 1)") },
    .{ "XML_PARAM_ENTITY_PARSING_ALWAYS", genConst("@as(i32, 2)") },
    .{ "version_info", genConst(".{ @as(i32, 2), @as(i32, 5), @as(i32, 0) }") },
    .{ "EXPAT_VERSION", genConst("\"expat_2.5.0\"") }, .{ "native_encoding", genConst("\"UTF-8\"") },
    .{ "features", genConst("&[_]struct { []const u8, i32 }{ .{ \"sizeof(XML_Char)\", 1 }, .{ \"sizeof(XML_LChar)\", 1 } }") },
    .{ "model", genConst(".{ .XML_CTYPE_EMPTY = 1, .XML_CTYPE_ANY = 2, .XML_CTYPE_MIXED = 3, .XML_CTYPE_NAME = 4, .XML_CTYPE_CHOICE = 5, .XML_CTYPE_SEQ = 6, .XML_CQUANT_NONE = 0, .XML_CQUANT_OPT = 1, .XML_CQUANT_REP = 2, .XML_CQUANT_PLUS = 3 }") },
    .{ "errors", genConst(".{ .XML_ERROR_NO_MEMORY = \"out of memory\", .XML_ERROR_SYNTAX = \"syntax error\", .XML_ERROR_NO_ELEMENTS = \"no element found\", .XML_ERROR_INVALID_TOKEN = \"not well-formed (invalid token)\" }") },
});
