/// Python imaplib module - IMAP4 protocol client
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "IMAP4", h.c(".{ .host = \"\", .port = @as(i32, 143), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }") },
    .{ "IMAP4_SSL", h.c(".{ .host = \"\", .port = @as(i32, 993), .state = \"LOGOUT\", .capabilities = &[_][]const u8{} }") },
    .{ "IMAP4_stream", h.c(".{ .host = \"\", .state = \"LOGOUT\" }") },
    .{ "IMAP4_PORT", h.I32(143) }, .{ "IMAP4_SSL_PORT", h.I32(993) }, .{ "Commands", h.c("@as(?*anyopaque, null)") },
    .{ "IMAP4.error", h.err("IMAP4Error") }, .{ "IMAP4.abort", h.err("IMAP4Abort") }, .{ "IMAP4.readonly", h.err("IMAP4Readonly") },
    .{ "Internaldate2tuple", h.c("@as(?*anyopaque, null)") }, .{ "Int2AP", h.c("\"\"") }, .{ "ParseFlags", h.c("&[_][]const u8{}") }, .{ "Time2Internaldate", h.c("\"\"") },
});
