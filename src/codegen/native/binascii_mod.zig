/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "hexlify", genHexlify }, .{ "unhexlify", genUnhexlify }, .{ "b2a_hex", genHexlify }, .{ "a2b_hex", genUnhexlify },
    .{ "b2a_base64", genB2a_base64 }, .{ "a2b_base64", genA2b_base64 },
    .{ "b2a_uu", h.c("\"\"") }, .{ "a2b_uu", h.c("\"\"") }, .{ "b2a_qp", h.c("\"\"") }, .{ "a2b_qp", h.c("\"\"") },
    .{ "crc32", genCrc32 }, .{ "crc_hqx", h.I32(0) },
    .{ "Error", h.err("BinasciiError") }, .{ "Incomplete", h.err("Incomplete") },
});

fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const _data = "); try self.genExpr(args[0]);
    try self.emit("; const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :blk \"\"; const _hex_chars = \"0123456789abcdef\"; for (_data, 0..) |b, i| { _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; } break :blk _hex; }");
}

fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const _hexstr = "); try self.genExpr(args[0]);
    try self.emit("; const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :blk \"\"; for (0..(_hexstr.len / 2)) |i| { const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0'; const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0'; _result[i] = (_hi << 4) | _lo; } break :blk _result; }");
}

const genB2a_base64 = h.b64enc("standard");
const genA2b_base64 = h.b64dec("standard");

fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(u32, 0)"); return; }
    try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk @as(u32, std.hash.crc.Crc32.hash(data)); }");
}
