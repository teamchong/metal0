/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const h = @import("mod_helper.zig");

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_hex: {{ const _data = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :__m{d}_hex \"\"; const _hex_chars = \"0123456789abcdef\"; for (_data, 0..) |b, i| {{ _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; }} break :__m{d}_hex _hex; }})", .{ id, id });
}

fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_unhex: {{ const _hexstr = ", .{id}); try self.genExpr(args[0]);
    try self.emitFmt("; const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :__m{d}_unhex \"\"; for (0..(_hexstr.len / 2)) |i| {{ const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0'; const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0'; _result[i] = (_hi << 4) | _lo; }} break :__m{d}_unhex _result; }})", .{ id, id });
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "hexlify", genHexlify }, .{ "unhexlify", genUnhexlify }, .{ "b2a_hex", genHexlify }, .{ "a2b_hex", genUnhexlify },
    .{ "b2a_base64", h.b64enc("standard") }, .{ "a2b_base64", h.b64dec("standard") },
    .{ "b2a_uu", h.c("\"\"") }, .{ "a2b_uu", h.c("\"\"") }, .{ "b2a_qp", h.c("\"\"") }, .{ "a2b_qp", h.c("\"\"") },
    .{ "crc32", h.wrap("@as(u32, std.hash.crc.Crc32.hash(", "))", "@as(u32, 0)") }, .{ "crc_hqx", h.I32(0) },
    .{ "Error", h.err("BinasciiError") }, .{ "Incomplete", h.err("Incomplete") },
});
