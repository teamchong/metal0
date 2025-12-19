/// Python binascii module - Binary/ASCII conversions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("hex", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _data = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :{s} \"\"; const _hex_chars = \"0123456789abcdef\"; for (_data, 0..) |b, i| {{ _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; }} break :{s} _hex", .{ label, label });
        }
    }.emit);
}

fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self, "\"\"");
        return;
    }
    try self.withInlineBlock("unhex", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const _hexstr = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :{s} \"\"; for (0..(_hexstr.len / 2)) |i| {{ const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0'; const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0'; _result[i] = (_hi << 4) | _lo; }} break :{s} _result", .{ label, label });
        }
    }.emit);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "hexlify", genHexlify }, .{ "unhexlify", genUnhexlify }, .{ "b2a_hex", genHexlify }, .{ "a2b_hex", genUnhexlify },
    .{ "b2a_base64", h.b64enc("standard") }, .{ "a2b_base64", h.b64dec("standard") },
    .{ "b2a_uu", h.c("\"\"") }, .{ "a2b_uu", h.c("\"\"") }, .{ "b2a_qp", h.c("\"\"") }, .{ "a2b_qp", h.c("\"\"") },
    .{ "crc32", h.wrap("@as(u32, std.hash.crc.Crc32.hash(", "))", "@as(u32, 0)") }, .{ "crc_hqx", h.I32(0) },
    .{ "Error", h.err("BinasciiError") }, .{ "Incomplete", h.err("Incomplete") },
});
