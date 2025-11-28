/// Python secrets module - cryptographically secure random numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate secrets.token_bytes(nbytes=32) -> bytes
pub fn genTokenBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("secrets_token_bytes_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _nbytes: usize = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_bytes_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.crypto.random.bytes(_buf);\n");
    try self.emitIndent();
    try self.emit("break :secrets_token_bytes_blk _buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.token_hex(nbytes=32) -> hex string
pub fn genTokenHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("secrets_token_hex_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _nbytes: usize = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_hex_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.crypto.random.bytes(_buf);\n");
    try self.emitIndent();
    try self.emit("var _hex = __global_allocator.alloc(u8, _nbytes * 2) catch break :secrets_token_hex_blk \"\";\n");
    try self.emitIndent();
    try self.emit("const _hex_chars = \"0123456789abcdef\";\n");
    try self.emitIndent();
    try self.emit("for (_buf, 0..) |b, i| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_hex[i * 2] = _hex_chars[b >> 4];\n");
    try self.emitIndent();
    try self.emit("_hex[i * 2 + 1] = _hex_chars[b & 0xf];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :secrets_token_hex_blk _hex;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.token_urlsafe(nbytes=32) -> base64 URL-safe string
pub fn genTokenUrlsafe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("secrets_token_urlsafe_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _nbytes: usize = ");
    if (args.len > 0) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_urlsafe_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.crypto.random.bytes(_buf);\n");
    try self.emitIndent();
    // URL-safe base64: use - and _ instead of + and /
    try self.emit("const _b64_chars = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_\";\n");
    try self.emitIndent();
    try self.emit("const _out_len = ((_nbytes * 4) + 2) / 3;\n");
    try self.emitIndent();
    try self.emit("var _result = __global_allocator.alloc(u8, _out_len) catch break :secrets_token_urlsafe_blk \"\";\n");
    try self.emitIndent();
    try self.emit("var _i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("var _j: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (_i < _nbytes) {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _n = @min(3, _nbytes - _i);\n");
    try self.emitIndent();
    try self.emit("var _val: u32 = 0;\n");
    try self.emitIndent();
    try self.emit("for (0.._n) |k| _val = (_val << 8) | _buf[_i + k];\n");
    try self.emitIndent();
    try self.emit("_val <<= @intCast((3 - _n) * 8);\n");
    try self.emitIndent();
    try self.emit("for (0..(_n + 1)) |k| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result[_j + k] = _b64_chars[@intCast((_val >> @intCast(18 - k * 6)) & 0x3f)];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("_i += _n;\n");
    try self.emitIndent();
    try self.emit("_j += _n + 1;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :secrets_token_urlsafe_blk _result[0.._j];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.randbelow(exclusive_upper_bound) -> int
pub fn genRandbelow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("secrets_randbelow_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _upper: u64 = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("if (_upper == 0) break :secrets_randbelow_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("break :secrets_randbelow_blk @as(i64, @intCast(std.crypto.random.intRangeLessThan(u64, 0, _upper)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.choice(sequence) -> element
pub fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("secrets_choice_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _seq = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (_seq.len == 0) break :secrets_choice_blk @as(@TypeOf(_seq[0]), undefined);\n");
    try self.emitIndent();
    try self.emit("const _idx = std.crypto.random.intRangeLessThan(usize, 0, _seq.len);\n");
    try self.emitIndent();
    try self.emit("break :secrets_choice_blk _seq[_idx];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.randbits(k) -> int with k random bits
pub fn genRandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("secrets_randbits_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _k: u6 = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("if (_k == 0) break :secrets_randbits_blk @as(i64, 0);\n");
    try self.emitIndent();
    try self.emit("const _mask: u64 = (@as(u64, 1) << _k) - 1;\n");
    try self.emitIndent();
    try self.emit("break :secrets_randbits_blk @as(i64, @intCast(std.crypto.random.int(u64) & _mask));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.compare_digest(a, b) -> bool (constant-time comparison)
pub fn genCompareDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("secrets_compare_blk: {\n");
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
    try self.emit("if (_a.len != _b.len) break :secrets_compare_blk false;\n");
    try self.emitIndent();
    try self.emit("var _result: u8 = 0;\n");
    try self.emitIndent();
    try self.emit("for (_a, _b) |a, b| _result |= a ^ b;\n");
    try self.emitIndent();
    try self.emit("break :secrets_compare_blk _result == 0;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate secrets.SystemRandom() -> SystemRandom instance
pub fn genSystemRandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a struct that mimics Python's SystemRandom
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn random(self: *@This()) f64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("const bits = std.crypto.random.int(u53);\n");
    try self.emitIndent();
    try self.emit("return @as(f64, @floatFromInt(bits)) / @as(f64, @floatFromInt(@as(u53, 1) << 53));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("pub fn randint(self: *@This(), a: i64, b: i64) i64 {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_ = self;\n");
    try self.emitIndent();
    try self.emit("return @as(i64, @intCast(std.crypto.random.intRangeAtMost(i64, a, b)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}
