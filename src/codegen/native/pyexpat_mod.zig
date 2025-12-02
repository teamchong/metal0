/// Python pyexpat module - Fast XML parsing using Expat
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ParserCreate", h.c(".{ .buffer_text = false, .buffer_size = 8192, .buffer_used = 0, .ordered_attributes = false, .specified_attributes = false, .returns_unicode = true }") },
    .{ "Parse", h.I32(1) }, .{ "ParseFile", h.I32(1) },
    .{ "SetBase", h.c("{}") }, .{ "GetBase", h.c("\"\"") }, .{ "GetInputContext", h.c("\"\"") },
    .{ "ExternalEntityParserCreate", h.c(".{}") }, .{ "SetParamEntityParsing", h.I32(1) }, .{ "UseForeignDTD", h.c("{}") },
    .{ "ErrorString", h.c("\"unknown error\"") }, .{ "XMLParserType", h.c("@TypeOf(.{})") },
    .{ "ExpatError", h.err("ExpatError") }, .{ "error", h.err("ExpatError") },
    .{ "XML_PARAM_ENTITY_PARSING_NEVER", h.I32(0) },
    .{ "XML_PARAM_ENTITY_PARSING_UNLESS_STANDALONE", h.I32(1) },
    .{ "XML_PARAM_ENTITY_PARSING_ALWAYS", h.I32(2) },
    .{ "version_info", h.c(".{ @as(i32, 2), @as(i32, 5), @as(i32, 0) }") },
    .{ "EXPAT_VERSION", h.c("\"expat_2.5.0\"") }, .{ "native_encoding", h.c("\"UTF-8\"") },
    .{ "features", h.c("&[_]struct { []const u8, i32 }{ .{ \"sizeof(XML_Char)\", 1 }, .{ \"sizeof(XML_LChar)\", 1 } }") },
    .{ "model", h.c(".{ .XML_CTYPE_EMPTY = 1, .XML_CTYPE_ANY = 2, .XML_CTYPE_MIXED = 3, .XML_CTYPE_NAME = 4, .XML_CTYPE_CHOICE = 5, .XML_CTYPE_SEQ = 6, .XML_CQUANT_NONE = 0, .XML_CQUANT_OPT = 1, .XML_CQUANT_REP = 2, .XML_CQUANT_PLUS = 3 }") },
    .{ "errors", h.c(".{ .XML_ERROR_NO_MEMORY = \"out of memory\", .XML_ERROR_SYNTAX = \"syntax error\", .XML_ERROR_NO_ELEMENTS = \"no element found\", .XML_ERROR_INVALID_TOKEN = \"not well-formed (invalid token)\" }") },
});
