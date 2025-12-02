/// Python uuid module - UUID generation
const std = @import("std");
const h = @import("mod_helper.zig");

const UuidFmt = "\"{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"";
const UuidArgs = ", .{ _bytes[0], _bytes[1], _bytes[2], _bytes[3], _bytes[4], _bytes[5], _bytes[6], _bytes[7], _bytes[8], _bytes[9], _bytes[10], _bytes[11], _bytes[12], _bytes[13], _bytes[14], _bytes[15] }) catch break :blk \"\"; break :blk &_buf; }";
const uuid4_impl = h.c("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; _rand.bytes(&_bytes); _bytes[6] = (_bytes[6] & 0x0f) | 0x40; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidArgs);
const uuid1_impl = h.c("blk: { const _ts = std.time.nanoTimestamp(); var _prng = std.Random.DefaultPrng.init(@intCast(_ts)); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; const _time_bytes = std.mem.asBytes(&_ts); @memcpy(_bytes[0..8], _time_bytes[0..8]); _rand.bytes(_bytes[8..16]); _bytes[6] = (_bytes[6] & 0x0f) | 0x10; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidArgs);

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "uuid4", uuid4_impl }, .{ "uuid1", uuid1_impl }, .{ "uuid3", uuid4_impl }, .{ "uuid5", uuid4_impl },
    .{ "UUID", h.pass("\"00000000-0000-0000-0000-000000000000\"") },
    .{ "NAMESPACE_DNS", h.c("\"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_URL", h.c("\"6ba7b811-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_OID", h.c("\"6ba7b812-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_X500", h.c("\"6ba7b814-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "getnode", h.c("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(_prng.random().int(u48))); }") },
});
