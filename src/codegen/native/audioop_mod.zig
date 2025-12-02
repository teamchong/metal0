/// Python audioop module - Audio operations
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "add", h.c("\"\"") }, .{ "alaw2lin", h.c("\"\"") }, .{ "bias", h.c("\"\"") }, .{ "byteswap", h.c("\"\"") },
    .{ "lin2alaw", h.c("\"\"") }, .{ "lin2lin", h.c("\"\"") }, .{ "lin2ulaw", h.c("\"\"") }, .{ "mul", h.c("\"\"") },
    .{ "reverse", h.c("\"\"") }, .{ "tomono", h.c("\"\"") }, .{ "tostereo", h.c("\"\"") }, .{ "ulaw2lin", h.c("\"\"") },
    .{ "avg", h.I32(0) }, .{ "avgpp", h.I32(0) }, .{ "cross", h.I32(0) }, .{ "findmax", h.I32(0) },
    .{ "getsample", h.I32(0) }, .{ "max", h.I32(0) }, .{ "maxpp", h.I32(0) }, .{ "rms", h.I32(0) },
    .{ "findfactor", h.F64(1.0) }, .{ "minmax", h.c(".{ @as(i32, 0), @as(i32, 0) }") }, .{ "findfit", h.c(".{ @as(i32, 0), @as(f64, 1.0) }") },
    .{ "adpcm2lin", h.c(".{ \"\", .{ @as(i32, 0), @as(i32, 0) } }") }, .{ "lin2adpcm", h.c(".{ \"\", .{ @as(i32, 0), @as(i32, 0) } }") },
    .{ "ratecv", h.c(".{ \"\", .{ @as(i32, 0), .{} } }") }, .{ "error", h.err("AudioopError") },
});
