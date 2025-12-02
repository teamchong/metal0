/// Python nntplib module - NNTP protocol client
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "NNTP", h.c(".{ .host = \"\", .port = @as(i32, 119), .timeout = @as(f64, -1.0) }") },
    .{ "NNTP_SSL", h.c(".{ .host = \"\", .port = @as(i32, 563), .timeout = @as(f64, -1.0) }") },
    .{ "NNTP_PORT", h.I32(119) }, .{ "NNTP_SSL_PORT", h.I32(563) },
    .{ "NNTPError", h.err("NNTPError") }, .{ "NNTPReplyError", h.err("NNTPReplyError") },
    .{ "NNTPTemporaryError", h.err("NNTPTemporaryError") }, .{ "NNTPPermanentError", h.err("NNTPPermanentError") },
    .{ "NNTPProtocolError", h.err("NNTPProtocolError") }, .{ "NNTPDataError", h.err("NNTPDataError") },
    .{ "GroupInfo", h.c(".{ .group = \"\", .last = @as(i32, 0), .first = @as(i32, 0), .flag = \"\" }") },
    .{ "ArticleInfo", h.c(".{ .number = @as(i32, 0), .message_id = \"\", .lines = &[_][]const u8{} }") },
    .{ "decode_header", h.pass("\"\"") },
});
