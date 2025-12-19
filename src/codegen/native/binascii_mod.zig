/// Python binascii module - Binary/ASCII conversions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("hex", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _data = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :{s} \"\"; const _hex_chars = \"0123456789abcdef\"; for (_data, 0..) |b, i| {{ _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; }} break :{s} _hex", .{ label, label });
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
        }
    }.emit);
}

fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("unhex", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b2 = try c.getBuilder();
            try b2.write("const _hexstr = ");
            const output1 = b2.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :{s} \"\"; for (0..(_hexstr.len / 2)) |i| {{ const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0'; const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0'; _result[i] = (_hi << 4) | _lo; }} break :{s} _result", .{ label, label });
                const output2 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
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
