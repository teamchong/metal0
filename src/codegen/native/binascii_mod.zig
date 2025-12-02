/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "hexlify", genHexlify }, .{ "unhexlify", genUnhexlify }, .{ "b2a_hex", genHexlify }, .{ "a2b_hex", genUnhexlify },
    .{ "b2a_base64", genB2a_base64 }, .{ "a2b_base64", genA2b_base64 },
    .{ "b2a_uu", genEmpty }, .{ "a2b_uu", genEmpty }, .{ "b2a_qp", genEmpty }, .{ "a2b_qp", genEmpty },
    .{ "crc32", genCrc32 }, .{ "crc_hqx", genCrc_hqx }, .{ "Error", genError }, .{ "Incomplete", genIncomplete },
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

fn genB2a_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const _data = "); try self.genExpr(args[0]);
    try self.emit("; const _encoder = std.base64.standard.Encoder; const _len = _encoder.calcSize(_data.len); const _buf = __global_allocator.alloc(u8, _len + 1) catch break :blk \"\"; _ = _encoder.encode(_buf[0.._len], _data); _buf[_len] = '\\n'; break :blk _buf; }");
}

fn genA2b_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"\""); return; }
    try self.emit("blk: { const _input = "); try self.genExpr(args[0]);
    try self.emit("; const _decoder = std.base64.standard.Decoder; const _len = _decoder.calcSizeForSlice(_input) catch break :blk \"\"; const _buf = __global_allocator.alloc(u8, _len) catch break :blk \"\"; _decoder.decode(_buf, _input) catch break :blk \"\"; break :blk _buf; }");
}

fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@as(u32, 0)"); return; }
    try self.emit("blk: { const data = "); try self.genExpr(args[0]); try self.emit("; break :blk @as(u32, std.hash.crc.Crc32.hash(data)); }");
}

fn genCrc_hqx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.BinasciiError"); }
fn genIncomplete(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.Incomplete"); }
