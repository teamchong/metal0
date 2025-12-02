/// Python xml.sax module - SAX XML parsing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "make_parser", h.c(".{}") }, .{ "parse", h.c("{}") }, .{ "parseString", h.c("{}") },
    .{ "ContentHandler", h.c(".{}") }, .{ "DTDHandler", h.c(".{}") }, .{ "EntityResolver", h.c(".{}") }, .{ "ErrorHandler", h.c(".{}") },
    .{ "InputSource", h.wrap("blk: { const system_id = ", "; break :blk .{ .system_id = system_id, .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }; }", ".{ .system_id = @as(?[]const u8, null), .public_id = @as(?[]const u8, null), .encoding = @as(?[]const u8, null), .byte_stream = @as(?*anyopaque, null), .character_stream = @as(?*anyopaque, null) }") },
    .{ "AttributesImpl", h.c(".{ .attrs = .{} }") }, .{ "AttributesNSImpl", h.c(".{ .attrs = .{}, .qnames = .{} }") },
    .{ "SAXException", h.err("SAXException") }, .{ "SAXNotRecognizedException", h.err("SAXNotRecognizedException") },
    .{ "SAXNotSupportedException", h.err("SAXNotSupportedException") }, .{ "SAXParseException", h.err("SAXParseException") },
});
