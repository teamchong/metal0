/// Python mailcap module - Mailcap file handling
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "findmatch", h.c("@as(?@TypeOf(.{ \"\", .{} }), null)") }, .{ "getcaps", h.c(".{}") },
    .{ "listmailcapfiles", h.c("&[_][]const u8{}") }, .{ "readmailcapfile", h.c(".{}") },
    .{ "lookup", h.c("&[_].{ []const u8, .{} }{}") }, .{ "subst", h.c("\"\"") },
});
