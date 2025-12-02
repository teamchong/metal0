/// Python hmac module - HMAC (Hash-based Message Authentication Code)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "new", genNew }, .{ "digest", genDigest }, .{ "compare_digest", genCompareDigest },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("hmac_new_blk: { const _key = ");
    try self.genExpr(args[0]);
    try self.emit("; const _msg = ");
    try self.genExpr(args[1]);
    try self.emit("; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); var _out: [32]u8 = undefined; _hmac.final(&_out); const _hex = __global_allocator.alloc(u8, 64) catch break :hmac_new_blk \"\"; const _hex_chars = \"0123456789abcdef\"; for (_out, 0..) |byte, i| { _hex[i * 2] = _hex_chars[byte >> 4]; _hex[i * 2 + 1] = _hex_chars[byte & 0x0f]; } break :hmac_new_blk _hex; }");
}

fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("hmac_digest_blk: { const _key = ");
    try self.genExpr(args[0]);
    try self.emit("; const _msg = ");
    try self.genExpr(args[1]);
    try self.emit("; var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key); _hmac.update(_msg); const _result = __global_allocator.alloc(u8, 32) catch break :hmac_digest_blk \"\"; _hmac.final(_result[0..32]); break :hmac_digest_blk _result; }");
}

fn genCompareDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const _a = ");
    try self.genExpr(args[0]);
    try self.emit("; const _b = ");
    try self.genExpr(args[1]);
    try self.emit("; if (_a.len != _b.len) break :blk false; var _diff: u8 = 0; for (_a, _b) |a_byte, b_byte| { _diff |= a_byte ^ b_byte; } break :blk _diff == 0; }");
}
