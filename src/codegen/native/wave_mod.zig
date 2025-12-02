/// Python wave module - WAV file handling
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.wrap("blk: { const f = ", "; break :blk .{ .file = f, .mode = \"rb\" }; }", ".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }") },
    .{ "Wave_read", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "Wave_write", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "Error", h.err("WaveError") },
});
