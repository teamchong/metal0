/// Python netrc module - netrc file parsing
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "netrc", h.structBlk("netrc", ".file = __v, .hosts = .{}, .macros = .{}", ".{ .file = @as(?[]const u8, null), .hosts = .{}, .macros = .{} }") },
    .{ "NetrcParseError", h.err("NetrcParseError") },
});
