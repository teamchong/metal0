/// Python ftplib module - FTP protocol client
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "FTP", h.c(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }") },
    .{ "FTP_TLS", h.c(".{ .host = \"\", .port = @as(i32, 21), .timeout = @as(f64, -1.0), .source_address = @as(?[]const u8, null), .encoding = \"utf-8\" }") },
    .{ "FTP_PORT", h.I32(21) },
    .{ "error", h.err("FTPError") }, .{ "error_reply", h.err("FTPReplyError") }, .{ "error_temp", h.err("FTPTempError") },
    .{ "error_perm", h.err("FTPPermError") }, .{ "error_proto", h.err("FTPProtoError") },
    .{ "all_errors", h.c("&[_]type{ error.FTPError, error.FTPReplyError, error.FTPTempError, error.FTPPermError, error.FTPProtoError }") },
});
