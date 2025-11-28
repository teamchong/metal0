/// Python base64 module - base64 encoding/decoding
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate base64.b64encode(data) -> bytes
pub fn genB64encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("base64_encode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _len = std.base64.standard.Encoder.calcSize(_data.len);\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _len) catch break :base64_encode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _result = std.base64.standard.Encoder.encode(_buf, _data);\n");
    try self.emitIndent();
    try self.emit("break :base64_encode_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.b64decode(data) -> bytes
pub fn genB64decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("base64_decode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _len = std.base64.standard.Decoder.calcSizeForSlice(_data) catch break :base64_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _len) catch break :base64_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.base64.standard.Decoder.decode(_buf, _data) catch break :base64_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :base64_decode_blk _buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.urlsafe_b64encode(data) -> bytes
pub fn genUrlsafeB64encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("base64_url_encode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _len = std.base64.url_safe.Encoder.calcSize(_data.len);\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _len) catch break :base64_url_encode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _result = std.base64.url_safe.Encoder.encode(_buf, _data);\n");
    try self.emitIndent();
    try self.emit("break :base64_url_encode_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.urlsafe_b64decode(data) -> bytes
pub fn genUrlsafeB64decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("base64_url_decode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _len = std.base64.url_safe.Decoder.calcSizeForSlice(_data) catch break :base64_url_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _len) catch break :base64_url_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.base64.url_safe.Decoder.decode(_buf, _data) catch break :base64_url_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :base64_url_decode_blk _buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.standard_b64encode(data) -> bytes
pub fn genStandardB64encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Standard is the same as regular b64encode
    try genB64encode(self, args);
}

/// Generate base64.standard_b64decode(data) -> bytes
pub fn genStandardB64decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Standard is the same as regular b64decode
    try genB64decode(self, args);
}

/// Generate base64.encodebytes(data) -> bytes
/// Like b64encode but inserts newlines every 76 chars
pub fn genEncodebytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // For simplicity, just use standard encode
    try genB64encode(self, args);
}

/// Generate base64.decodebytes(data) -> bytes
/// Decode with optional whitespace
pub fn genDecodebytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genB64decode(self, args);
}

/// Generate base64.b32encode(data) -> bytes
pub fn genB32encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Zig std doesn't have base32, so we emit a placeholder
    try self.emit("base32_encode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _data;\n");
    try self.emitIndent();
    try self.emit("break :base32_encode_blk \"base32_not_implemented\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.b32decode(data) -> bytes
pub fn genB32decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("base32_decode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _data;\n");
    try self.emitIndent();
    try self.emit("break :base32_decode_blk \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.b16encode(data) -> bytes (hex encode)
pub fn genB16encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("hex_encode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _data.len * 2) catch break :hex_encode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_ = std.fmt.bufPrint(_buf, \"{s}\", .{std.fmt.fmtSliceHexUpper(_data)}) catch break :hex_encode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :hex_encode_blk _buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.b16decode(data) -> bytes (hex decode)
pub fn genB16decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("hex_decode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _data.len / 2) catch break :hex_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_ = std.fmt.hexToBytes(_buf, _data) catch break :hex_decode_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :hex_decode_blk _buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.a85encode(data) -> bytes (ASCII85)
pub fn genA85encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Placeholder - Zig std doesn't have ASCII85
    try self.emit("a85_encode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _data;\n");
    try self.emitIndent();
    try self.emit("break :a85_encode_blk \"a85_not_implemented\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate base64.a85decode(data) -> bytes (ASCII85)
pub fn genA85decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("a85_decode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _data = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("_ = _data;\n");
    try self.emitIndent();
    try self.emit("break :a85_decode_blk \"\";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
