/// Python trace module - Trace execution of Python programs
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Trace", h.c(".{ .count = true, .trace = true, .countfuncs = false, .countcallers = false, .ignoremods = &[_][]const u8{}, .ignoredirs = &[_][]const u8{}, .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }") },
    .{ "CoverageResults", h.c(".{ .counts = @as(?*anyopaque, null), .counter = @as(?*anyopaque, null), .calledfuncs = @as(?*anyopaque, null), .callers = @as(?*anyopaque, null), .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }") },
});
