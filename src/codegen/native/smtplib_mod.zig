/// Python smtplib module - SMTP protocol client
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SMTP", h.c(".{ .host = \"\", .port = @as(i32, 25), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }") },
    .{ "SMTP_SSL", h.c(".{ .host = \"\", .port = @as(i32, 465), .local_hostname = @as(?[]const u8, null), .timeout = @as(f64, 30.0), .source_address = @as(?[]const u8, null) }") },
    .{ "LMTP", h.c(".{ .host = \"\", .port = @as(i32, 2003), .local_hostname = @as(?[]const u8, null) }") },
    .{ "SMTP_PORT", h.I32(25) }, .{ "SMTP_SSL_PORT", h.I32(465) },
    .{ "SMTPException", h.err("SMTPException") }, .{ "SMTPServerDisconnected", h.err("SMTPServerDisconnected") },
    .{ "SMTPResponseException", h.err("SMTPResponseException") }, .{ "SMTPSenderRefused", h.err("SMTPSenderRefused") },
    .{ "SMTPRecipientsRefused", h.err("SMTPRecipientsRefused") }, .{ "SMTPDataError", h.err("SMTPDataError") },
    .{ "SMTPConnectError", h.err("SMTPConnectError") }, .{ "SMTPHeloError", h.err("SMTPHeloError") },
    .{ "SMTPAuthenticationError", h.err("SMTPAuthenticationError") }, .{ "SMTPNotSupportedError", h.err("SMTPNotSupportedError") },
});
