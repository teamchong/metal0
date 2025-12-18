/// Python base64 module - base64 encoding/decoding
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");

// Public exports for dispatch/builtins.zig
pub const genB64encode = h.b64enc("standard");
pub const genB64decode = h.b64dec("standard");
pub const genUrlsafeB64encode = h.b64enc("url_safe");
pub const genUrlsafeB64decode = h.b64dec("url_safe");

const genB16encode = h.wrapBlk("b16e", "const _buf = __global_allocator.alloc(u8, __v.len * 2) catch unreachable; _ = std.fmt.bufPrint(_buf, \"{s}\", .{std.fmt.fmtSliceHexUpper(__v)}) catch unreachable;", "_buf", "\"\"");
const genB16decode = h.wrapBlk("b16d", "const _buf = __global_allocator.alloc(u8, __v.len / 2) catch unreachable; _ = std.fmt.hexToBytes(_buf, __v) catch unreachable;", "_buf", "\"\"");
const genZ85encode = h.wrapBlk("z85e", "if (__v.len % 4 != 0) unreachable; const _z = \"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#\"; const _buf = __global_allocator.alloc(u8, __v.len * 5 / 4) catch unreachable; var _i: usize = 0; var _j: usize = 0; while (_i < __v.len) : ({ _i += 4; _j += 5; }) { var _x: u32 = (@as(u32, __v[_i]) << 24) | (@as(u32, __v[_i+1]) << 16) | (@as(u32, __v[_i+2]) << 8) | @as(u32, __v[_i+3]); var _k: usize = 5; while (_k > 0) : (_k -= 1) { _buf[_j + _k - 1] = _z[@as(usize, @intCast(_x % 85))]; _x /= 85; } }", "_buf", "\"\"");
const genZ85decode = h.wrapBlk("z85d", "if (__v.len % 5 != 0) unreachable; const _z = \"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#\"; var _dec: [256]u8 = undefined; for (_z, 0..) |_c, _x| { _dec[_c] = @as(u8, @intCast(_x)); } const _buf = __global_allocator.alloc(u8, __v.len * 4 / 5) catch unreachable; var _i: usize = 0; var _j: usize = 0; while (_i < __v.len) : ({ _i += 5; _j += 4; }) { var _x: u32 = 0; for (0..5) |_k| { _x = _x * 85 + @as(u32, _dec[__v[_i + _k]]); } _buf[_j] = @as(u8, @intCast((_x >> 24) & 0xFF)); _buf[_j+1] = @as(u8, @intCast((_x >> 16) & 0xFF)); _buf[_j+2] = @as(u8, @intCast((_x >> 8) & 0xFF)); _buf[_j+3] = @as(u8, @intCast(_x & 0xFF)); }", "_buf", "\"\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "b64encode", genB64encode }, .{ "b64decode", genB64decode },
    .{ "urlsafe_b64encode", genUrlsafeB64encode }, .{ "urlsafe_b64decode", genUrlsafeB64decode },
    .{ "standard_b64encode", h.b64enc("standard") }, .{ "standard_b64decode", h.b64dec("standard") },
    .{ "encodebytes", h.b64enc("standard") }, .{ "decodebytes", h.b64dec("standard") },
    .{ "b32encode", h.stub("\"base32_not_impl\"") }, .{ "b32decode", h.stub("\"\"") },
    .{ "b16encode", genB16encode }, .{ "b16decode", genB16decode },
    .{ "a85encode", h.stub("\"a85_not_impl\"") }, .{ "a85decode", h.stub("\"\"") },
    .{ "z85encode", genZ85encode }, .{ "z85decode", genZ85decode },
});
