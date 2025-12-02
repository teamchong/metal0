/// Python unicodedata module - Unicode character database
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "lookup", h.discard("\"?\"") }, .{ "name", h.discard("\"UNKNOWN\"") },
    .{ "decimal", h.charFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "digit", h.charFunc("blk", "@as(i32, -1)", "if (c >= '0' and c <= '9') break :blk @as(i32, c - '0') else break :blk -1;") },
    .{ "numeric", h.charFunc("blk", "@as(f64, -1.0)", "if (c >= '0' and c <= '9') break :blk @as(f64, @floatFromInt(c - '0')) else break :blk -1.0;") },
    .{ "category", h.charFunc("blk", "\"Cn\"", "if (c >= 'a' and c <= 'z') break :blk \"Ll\" else if (c >= 'A' and c <= 'Z') break :blk \"Lu\" else if (c >= '0' and c <= '9') break :blk \"Nd\" else if (c == ' ') break :blk \"Zs\" else break :blk \"Cn\";") },
    .{ "bidirectional", h.charFunc("blk", "\"\"", "if (c >= 'a' and c <= 'z') break :blk \"L\" else if (c >= 'A' and c <= 'Z') break :blk \"L\" else if (c >= '0' and c <= '9') break :blk \"EN\" else break :blk \"ON\";") },
    .{ "combining", h.I32(0) }, .{ "east_asian_width", h.c("\"N\"") },
    .{ "mirrored", h.I32(0) }, .{ "decomposition", h.c("\"\"") },
    .{ "normalize", h.passN(1, "\"\"") }, .{ "is_normalized", h.c("true") },
    .{ "unidata_version", h.c("\"15.0.0\"") }, .{ "ucd_3_2_0", h.c(".{}") },
});
