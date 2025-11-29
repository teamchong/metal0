/// Python binascii module - Binary/ASCII conversions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate binascii.hexlify(data, sep=None, bytes_per_sep=1)
pub fn genHexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("binascii_hexlify_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _data = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _hex = __global_allocator.alloc(u8, _data.len * 2) catch break :binascii_hexlify_blk \"\";\n");
        try self.emitIndent();
        try self.emit("const _hex_chars = \"0123456789abcdef\";\n");
        try self.emitIndent();
        try self.emit("for (_data, 0..) |b, i| {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("_hex[i * 2] = _hex_chars[b >> 4];\n");
        try self.emitIndent();
        try self.emit("_hex[i * 2 + 1] = _hex_chars[b & 0xf];\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.emit("break :binascii_hexlify_blk _hex;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate binascii.unhexlify(hexstr)
pub fn genUnhexlify(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("binascii_unhexlify_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _hexstr = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _result = __global_allocator.alloc(u8, _hexstr.len / 2) catch break :binascii_unhexlify_blk \"\";\n");
        try self.emitIndent();
        try self.emit("for (0..(_hexstr.len / 2)) |i| {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _hi = if (_hexstr[i * 2] >= 'a') _hexstr[i * 2] - 'a' + 10 else if (_hexstr[i * 2] >= 'A') _hexstr[i * 2] - 'A' + 10 else _hexstr[i * 2] - '0';\n");
        try self.emitIndent();
        try self.emit("const _lo = if (_hexstr[i * 2 + 1] >= 'a') _hexstr[i * 2 + 1] - 'a' + 10 else if (_hexstr[i * 2 + 1] >= 'A') _hexstr[i * 2 + 1] - 'A' + 10 else _hexstr[i * 2 + 1] - '0';\n");
        try self.emitIndent();
        try self.emit("_result[i] = (_hi << 4) | _lo;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        try self.emitIndent();
        try self.emit("break :binascii_unhexlify_blk _result;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate binascii.b2a_hex(data) - same as hexlify
pub fn genB2a_hex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genHexlify(self, args);
}

/// Generate binascii.a2b_hex(hexstr) - same as unhexlify
pub fn genA2b_hex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    return genUnhexlify(self, args);
}

/// Generate binascii.b2a_base64(data, newline=True)
pub fn genB2a_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("binascii_b2a_base64_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _data = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _encoder = std.base64.standard.Encoder;\n");
        try self.emitIndent();
        try self.emit("const _len = _encoder.calcSize(_data.len);\n");
        try self.emitIndent();
        try self.emit("const _buf = __global_allocator.alloc(u8, _len + 1) catch break :binascii_b2a_base64_blk \"\";\n");
        try self.emitIndent();
        try self.emit("_ = _encoder.encode(_buf[0.._len], _data);\n");
        try self.emitIndent();
        try self.emit("_buf[_len] = '\\n';\n");
        try self.emitIndent();
        try self.emit("break :binascii_b2a_base64_blk _buf;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate binascii.a2b_base64(string)
pub fn genA2b_base64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("binascii_a2b_base64_blk: {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("const _input = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("const _decoder = std.base64.standard.Decoder;\n");
        try self.emitIndent();
        try self.emit("const _len = _decoder.calcSizeForSlice(_input) catch break :binascii_a2b_base64_blk \"\";\n");
        try self.emitIndent();
        try self.emit("const _buf = __global_allocator.alloc(u8, _len) catch break :binascii_a2b_base64_blk \"\";\n");
        try self.emitIndent();
        try self.emit("_decoder.decode(_buf, _input) catch break :binascii_a2b_base64_blk \"\";\n");
        try self.emitIndent();
        try self.emit("break :binascii_a2b_base64_blk _buf;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}");
    } else {
        try self.emit("\"\"");
    }
}

/// Generate binascii.b2a_uu(data, backtick=False)
pub fn genB2a_uu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.a2b_uu(string)
pub fn genA2b_uu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.b2a_qp(data, quotetabs=False, istext=True, header=False)
pub fn genB2a_qp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.a2b_qp(string, header=False)
pub fn genA2b_qp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate binascii.crc32(data, crc=0)
pub fn genCrc32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const data = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk @as(u32, std.hash.crc.Crc32.hash(data)); }");
    } else {
        try self.emit("@as(u32, 0)");
    }
}

/// Generate binascii.crc_hqx(data, crc)
pub fn genCrc_hqx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate binascii.Error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BinasciiError");
}

/// Generate binascii.Incomplete exception
pub fn genIncomplete(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Incomplete");
}
