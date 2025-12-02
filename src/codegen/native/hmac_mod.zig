/// Python hmac module - HMAC (Hash-based Message Authentication Code)
const std = @import("std");
const h = @import("mod_helper.zig");

const newBody = "; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); var _out: [32]u8 = undefined; _hmac.final(&_out); const _hex = __global_allocator.alloc(u8, 64) catch break :hmac_new_blk \"\"; const _hex_chars = \"0123456789abcdef\"; for (_out, 0..) |byte, i| { _hex[i * 2] = _hex_chars[byte >> 4]; _hex[i * 2 + 1] = _hex_chars[byte & 0x0f]; } break :hmac_new_blk _hex; }";
const digestBody = "; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); const _result = __global_allocator.alloc(u8, 32) catch break :hmac_digest_blk \"\"; _hmac.final(_result[0..32]); break :hmac_digest_blk _result; }";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new", h.wrap2("hmac_new_blk: { const _key = ", "; const _msg = ", newBody, "\"\"") },
    .{ "digest", h.wrap2("hmac_digest_blk: { const _key = ", "; const _msg = ", digestBody, "\"\"") },
    .{ "compare_digest", h.compareDigest() },
});

