/// Python secrets module - cryptographically secure random numbers
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "token_bytes", genTokenBytes }, .{ "token_hex", genTokenHex }, .{ "token_urlsafe", genTokenUrlsafe },
    .{ "randbelow", genRandbelow }, .{ "choice", genChoice }, .{ "randbits", genRandbits },
    .{ "compare_digest", genCompareDigest },
    .{ "SystemRandom", genConst("struct { pub fn random(__self: *@This()) f64 { _ = __self; const bits = std.crypto.random.int(u53); return @as(f64, @floatFromInt(bits)) / @as(f64, @floatFromInt(@as(u53, 1) << 53)); } pub fn randint(__self: *@This(), a: i64, b: i64) i64 { _ = __self; return @as(i64, @intCast(std.crypto.random.intRangeAtMost(i64, a, b))); } }{}") },
    .{ "DEFAULT_ENTROPY", genConst("@as(i64, 32)") },
});

const nbytes_init = "const _nbytes: usize = ";
const nbytes_alloc = "; const _buf = __global_allocator.alloc(u8, _nbytes) catch break :blk \"\"; std.crypto.random.bytes(_buf);";

fn isNoneArg(arg: ast.Node) bool {
    return (arg == .constant and arg.constant.value == .none) or (arg == .name and std.mem.eql(u8, arg.name.id, "None"));
}
fn emitNbytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(nbytes_init);
    if (args.len > 0 and !isNoneArg(args[0])) { try self.emit("@intCast("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("32");
    try self.emit(nbytes_alloc);
}

fn genTokenBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("blk: { "); try emitNbytes(self, args); try self.emit(" break :blk _buf; }");
}
fn genTokenHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("blk: { "); try emitNbytes(self, args);
    try self.emit(" const _hex = __global_allocator.alloc(u8, _nbytes * 2) catch break :blk \"\"; const _hex_chars = \"0123456789abcdef\"; for (_buf, 0..) |b, i| { _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; } break :blk _hex; }");
}
fn genTokenUrlsafe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("blk: { "); try emitNbytes(self, args);
    try self.emit(" const _encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(_nbytes); const _result = __global_allocator.alloc(u8, _encoded_len) catch break :blk \"\"; _ = std.base64.url_safe_no_pad.Encoder.encode(_result, _buf); break :blk _result; }");
}
fn genRandbelow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _upper_raw: i64 = @intCast("); try self.genExpr(args[0]);
    try self.emit("); if (_upper_raw <= 0) return error.ValueError; const _upper: u64 = @intCast(_upper_raw); break :blk @as(i64, @intCast(std.crypto.random.intRangeLessThan(u64, 0, _upper))); }");
}
fn genChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _seq = "); try self.genExpr(args[0]);
    try self.emit("; if (_seq.len == 0) break :blk @as(@TypeOf(_seq[0]), undefined); const _idx = std.crypto.random.intRangeLessThan(usize, 0, _seq.len); break :blk _seq[_idx]; }");
}
fn genRandbits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const _k: u6 = @intCast("); try self.genExpr(args[0]);
    try self.emit("); if (_k == 0) break :blk @as(i64, 0); const _mask: u64 = (@as(u64, 1) << _k) - 1; break :blk @as(i64, @intCast(std.crypto.random.int(u64) & _mask)); }");
}
fn genCompareDigest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("blk: { const __cmp_left = "); try self.genExpr(args[0]); try self.emit("; const __cmp_right = "); try self.genExpr(args[1]);
    try self.emit("; if (__cmp_left.len != __cmp_right.len) break :blk false; var __cmp_result: u8 = 0; for (__cmp_left, __cmp_right) |__cmp_ca, __cmp_cb| __cmp_result |= __cmp_ca ^ __cmp_cb; break :blk __cmp_result == 0; }");
}
