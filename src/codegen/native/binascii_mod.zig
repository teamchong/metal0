/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const h = @import("mod_helper.zig");

const hexlifyBody = "; const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :blk \"\"; const _hex_chars = \"0123456789abcdef\"; for (_data, 0..) |b, i| { _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; } break :blk _hex; }";
const unhexlifyBody = "; const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :blk \"\"; for (0..(_hexstr.len / 2)) |i| { const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0'; const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0'; _result[i] = (_hi << 4) | _lo; } break :blk _result; }";
const genHexlify = h.wrap("blk: { const _data = ", hexlifyBody, "\"\"");
const genUnhexlify = h.wrap("blk: { const _hexstr = ", unhexlifyBody, "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "hexlify", genHexlify }, .{ "unhexlify", genUnhexlify }, .{ "b2a_hex", genHexlify }, .{ "a2b_hex", genUnhexlify },
    .{ "b2a_base64", h.b64enc("standard") }, .{ "a2b_base64", h.b64dec("standard") },
    .{ "b2a_uu", h.c("\"\"") }, .{ "a2b_uu", h.c("\"\"") }, .{ "b2a_qp", h.c("\"\"") }, .{ "a2b_qp", h.c("\"\"") },
    .{ "crc32", h.wrap("@as(u32, std.hash.crc.Crc32.hash(", "))", "@as(u32, 0)") }, .{ "crc_hqx", h.I32(0) },
    .{ "Error", h.err("BinasciiError") }, .{ "Incomplete", h.err("Incomplete") },
});
