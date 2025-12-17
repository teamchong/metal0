/// Python _struct module - C accelerator for struct (internal)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pack", h.wrapBlk("pk", "_ = __v; var _result: std.ArrayList(u8) = .{};", "_result.items", "\"\"") },
    .{ "pack_into", h.c("{}") },
    .{ "unpack", h.wrap2Blk("unp", "_ = __v0; _ = __v1;", ".{}", ".{}") },
    .{ "unpack_from", h.wrap2Blk("unpf", "_ = __v0; _ = __v1;", ".{}", ".{}") },
    .{ "iter_unpack", h.c("&[_]@TypeOf(.{}){}") },
    .{ "calcsize", h.wrapBlk("csz", "var _size: i64 = 0; for (__v) |c| { switch (c) { 'b', 'B', 'c', '?', 's', 'p' => _size += 1, 'h', 'H' => _size += 2, 'i', 'I', 'l', 'L', 'f' => _size += 4, 'q', 'Q', 'd' => _size += 8, else => {}, } }", "_size", "@as(i64, 0)") },
    .{ "Struct", h.wrapBlk("st", "", ".{ .format = __v, .size = 0 }", ".{ .format = \"\", .size = 0 }") },
    .{ "error", h.err("StructError") },
});
