/// Python dbm module - Interfaces to Unix databases
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.wrap("blk: { const path = ", "; break :blk .{ .path = path, .data = metal0_runtime.PyDict([]const u8, []const u8).init() }; }", ".{ .path = \"\", .data = metal0_runtime.PyDict([]const u8, []const u8).init() }") }, .{ "error", h.err("DbmError") }, .{ "whichdb", h.c("@as(?[]const u8, \"dbm.dumb\")") },
});
