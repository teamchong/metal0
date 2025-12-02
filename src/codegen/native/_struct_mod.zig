/// Python _struct module - C accelerator for struct (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pack", h.wrap("blk: { const fmt = ", "; _ = fmt; var result: std.ArrayList(u8) = .{}; break :blk result.items; }", "\"\"") },
    .{ "pack_into", h.c("{}") },
    .{ "unpack", h.wrap2("blk: { const fmt = ", "; const buffer = ", "; _ = fmt; _ = buffer; break :blk .{}; }", ".{}") },
    .{ "unpack_from", h.wrap2("blk: { const fmt = ", "; const buffer = ", "; _ = fmt; _ = buffer; break :blk .{}; }", ".{}") },
    .{ "iter_unpack", h.c("&[_]@TypeOf(.{}){}") },
    .{ "calcsize", h.wrap("blk: { const fmt = ", "; var size: i64 = 0; for (fmt) |c| { switch (c) { 'b', 'B', 'c', '?', 's', 'p' => size += 1, 'h', 'H' => size += 2, 'i', 'I', 'l', 'L', 'f' => size += 4, 'q', 'Q', 'd' => size += 8, else => {}, } } break :blk size; }", "@as(i64, 0)") },
    .{ "Struct", h.wrap("blk: { const fmt = ", "; break :blk .{ .format = fmt, .size = 0 }; }", ".{ .format = \"\", .size = 0 }") },
    .{ "error", h.err("StructError") },
});
