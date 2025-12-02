/// Python aifc module - AIFF/AIFC file handling
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.wrap("blk: { const f = ", "; break :blk .{ .file = f, .mode = \"rb\" }; }", ".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }") }, .{ "Error", h.err("AifcError") },
    .{ "Aifc_read", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "Aifc_write", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
});
