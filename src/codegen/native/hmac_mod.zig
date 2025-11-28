/// Python hmac module - HMAC (Hash-based Message Authentication Code)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate hmac.new(key, msg, digestmod) -> HMAC object
/// For now, returns the computed HMAC directly (no object)
pub fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("hmac_new_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _key = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    // Default to sha256 if digestmod not specified
    try self.emit("var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key);\n");
    try self.emitIndent();
    try self.emit("_hmac.update(_msg);\n");
    try self.emitIndent();
    try self.emit("var _out: [32]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("_hmac.final(&_out);\n");
    try self.emitIndent();
    // Convert to hex string
    try self.emit("const _hex = __global_allocator.alloc(u8, 64) catch break :hmac_new_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _hex_chars = \"0123456789abcdef\";\n");
    try self.emitIndent();
    try self.emit("for (_out, 0..) |byte, i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_hex[i * 2] = _hex_chars[byte >> 4];\n");
    try self.emitIndent();
    try self.emit("_hex[i * 2 + 1] = _hex_chars[byte & 0x0f];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :hmac_new_blk _hex;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate hmac.digest(key, msg, digestmod) -> bytes
/// One-shot HMAC computation returning raw digest bytes
pub fn genDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("hmac_digest_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _key = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _msg = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(_key);\n");
    try self.emitIndent();
    try self.emit("_hmac.update(_msg);\n");
    try self.emitIndent();
    try self.emit("const _result = __global_allocator.alloc(u8, 32) catch break :hmac_digest_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_hmac.final(_result[0..32]);\n");
    try self.emitIndent();
    try self.emit("break :hmac_digest_blk _result;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate hmac.compare_digest(a, b) -> bool
/// Constant-time comparison of two digests
pub fn genCompareDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _a = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _b = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    // Use constant-time comparison
    try self.emit("if (_a.len != _b.len) break :blk false;\n");
    try self.emitIndent();
    try self.emit("var _diff: u8 = 0;\n");
    try self.emitIndent();
    try self.emit("for (_a, _b) |a_byte, b_byte| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_diff |= a_byte ^ b_byte;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :blk _diff == 0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
