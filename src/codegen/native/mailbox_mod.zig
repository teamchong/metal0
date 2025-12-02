/// Python mailbox module - Mailbox handling
const std = @import("std");
const h = @import("mod_helper.zig");

const genMailboxType = h.wrap("blk: { const path = ", "; break :blk .{ .path = path, .factory = @as(?*anyopaque, null), .create = true }; }", ".{ .path = \"\", .factory = @as(?*anyopaque, null), .create = true }");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Mailbox", genMailboxType }, .{ "Maildir", genMailboxType }, .{ "mbox", genMailboxType },
    .{ "MH", genMailboxType }, .{ "Babyl", genMailboxType }, .{ "MMDF", genMailboxType },
    .{ "Message", h.c(".{}") },
    .{ "MaildirMessage", h.c(".{ .subdir = \"new\", .info = \"\", .date = @as(f64, 0) }") },
    .{ "mboxMessage", h.c(".{ .from_ = \"\" }") }, .{ "MMDFMessage", h.c(".{ .from_ = \"\" }") },
    .{ "MHMessage", h.c(".{ .sequences = &[_][]const u8{} }") },
    .{ "BabylMessage", h.c(".{ .labels = &[_][]const u8{} }") },
    .{ "Error", h.err("MailboxError") }, .{ "NoSuchMailboxError", h.err("NoSuchMailboxError") },
    .{ "NotEmptyError", h.err("NotEmptyError") }, .{ "ExternalClashError", h.err("ExternalClashError") },
    .{ "FormatError", h.err("FormatError") },
});
