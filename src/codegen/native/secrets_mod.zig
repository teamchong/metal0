/// Python secrets module - cryptographically secure random numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "token_bytes", genTokenBytes },
    .{ "token_hex", genTokenHex },
    .{ "token_urlsafe", genTokenUrlsafe },
    .{ "randbelow", genRandbelow },
    .{ "choice", genChoice },
    .{ "randbits", genRandbits },
    .{ "compare_digest", genCompareDigest },
    .{ "SystemRandom", genSystemRandom },
    .{ "DEFAULT_ENTROPY", genDefaultEntropy },
});

/// Generate secrets.DEFAULT_ENTROPY constant (32 bytes)
pub fn genDefaultEntropy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 32)");
}

/// Check if argument is None constant
fn isNoneArg(arg: ast.Node) bool {
    if (arg == .constant) {
        if (arg.constant.value == .none) return true;
    }
    if (arg == .name) {
        if (std.mem.eql(u8, arg.name.id, "None")) return true;
    }
    return false;
}

/// Generate secrets.token_bytes(nbytes=32) -> bytes
pub fn genTokenBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("secrets_token_bytes_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _nbytes: usize = ");
    if (args.len > 0 and !isNoneArg(args[0])) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_bytes_blk \"\";\n");
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
    if (args.len > 0 and !isNoneArg(args[0])) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_hex_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.crypto.random.bytes(_buf);\n");
    try self.emitIndent();
    try self.emit("const _hex = __global_allocator.alloc(u8, _nbytes * 2) catch break :secrets_token_hex_blk \"\";\n");
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
    if (args.len > 0 and !isNoneArg(args[0])) {
        try self.emit("@intCast(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("32");
    }
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _buf = __global_allocator.alloc(u8, _nbytes) catch break :secrets_token_urlsafe_blk \"\";\n");
    try self.emitIndent();
    try self.emit("std.crypto.random.bytes(_buf);\n");
    try self.emitIndent();
    // Use Zig's built-in base64 URL-safe encoder
    try self.emit("const _encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(_nbytes);\n");
    try self.emitIndent();
    try self.emit("const _result = __global_allocator.alloc(u8, _encoded_len) catch break :secrets_token_urlsafe_blk \"\";\n");
    try self.emitIndent();
    try self.emit("_ = std.base64.url_safe_no_pad.Encoder.encode(_result, _buf);\n");
    try self.emitIndent();
    try self.emit("break :secrets_token_urlsafe_blk _result;\n");
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
    try self.emit("const _upper_raw: i64 = @intCast(");
    try self.genExpr(args[0]);
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("if (_upper_raw <= 0) return error.ValueError;\n");
    try self.emitIndent();
    try self.emit("const _upper: u64 = @intCast(_upper_raw);\n");
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
    try self.emit("const __cmp_left = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const __cmp_right = ");
    try self.genExpr(args[1]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("if (__cmp_left.len != __cmp_right.len) break :secrets_compare_blk false;\n");
    try self.emitIndent();
    try self.emit("var __cmp_result: u8 = 0;\n");
    try self.emitIndent();
    try self.emit("for (__cmp_left, __cmp_right) |__cmp_ca, __cmp_cb| __cmp_result |= __cmp_ca ^ __cmp_cb;\n");
    try self.emitIndent();
    try self.emit("break :secrets_compare_blk __cmp_result == 0;\n");
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
    try self.emit("pub fn random(__self: *@This()) f64 {\n");
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
    try self.emit("pub fn randint(__self: *@This(), a: i64, b: i64) i64 {\n");
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
