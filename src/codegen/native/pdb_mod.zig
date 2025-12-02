/// Python pdb module - Python debugger
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Pdb", h.c(".{ .skip = @as(?[]const []const u8, null), .nosigint = false }") },
    .{ "run", h.c("{}") }, .{ "runeval", h.c("@as(?*anyopaque, null)") }, .{ "runcall", h.c("@as(?*anyopaque, null)") },
    .{ "set_trace", h.c("{}") }, .{ "post_mortem", h.c("{}") }, .{ "pm", h.c("{}") }, .{ "help", h.c("{}") },
    .{ "Breakpoint", h.c(".{ .file = \"\", .line = @as(i32, 0), .temporary = false, .cond = @as(?[]const u8, null), .funcname = @as(?[]const u8, null), .enabled = true, .ignore = @as(i32, 0), .hits = @as(i32, 0), .number = @as(i32, 0) }") },
});
