/// Python _multibytecodec module - Multi-byte codec support
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "multibyte_codec", h.c(".{ .name = \"\" }") }, .{ "multibyte_incremental_encoder", h.c(".{ .codec = null, .errors = \"strict\" }") }, .{ "multibyte_incremental_decoder", h.c(".{ .codec = null, .errors = \"strict\" }") },
    .{ "multibyte_stream_reader", h.c(".{ .stream = null, .errors = \"strict\" }") }, .{ "multibyte_stream_writer", h.c(".{ .stream = null, .errors = \"strict\" }") }, .{ "create_codec", h.c(".{ .name = \"\" }") },
});
