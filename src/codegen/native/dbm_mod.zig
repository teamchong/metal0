/// Python dbm module - Interfaces to Unix databases
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.structBlk("dbm", ".path = __v, .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator)", ".{ .path = \"\", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }") }, .{ "error", h.err("DbmError") }, .{ "whichdb", h.c("@as(?[]const u8, \"dbm.dumb\")") },
});
