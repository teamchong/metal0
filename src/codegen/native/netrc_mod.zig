/// Python netrc module - netrc file parsing
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "netrc", h.wrap("blk: { const file = ", "; break :blk .{ .file = file, .hosts = .{}, .macros = .{} }; }", ".{ .file = @as(?[]const u8, null), .hosts = .{}, .macros = .{} }") },
    .{ "NetrcParseError", h.err("NetrcParseError") },
});
