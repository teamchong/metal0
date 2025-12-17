/// Python secrets module - cryptographically secure random numbers
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Note: These static string maps cannot use dynamic IDs from nextNameId()
// They are compile-time constants, so we use descriptive static labels instead
pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "token_bytes", genTokenBytes }, .{ "token_hex", genTokenHex }, .{ "token_urlsafe", genTokenUrlsafe },
    .{ "randbelow", h.wrap("__m_randbelow: { const _upper_raw: i64 = @intCast(", "); if (_upper_raw <= 0) return error.ValueError; const _upper: u64 = @intCast(_upper_raw); break :__m_randbelow @as(i64, @intCast(std.crypto.random.intRangeLessThan(u64, 0, _upper))); }", "0") },
    .{ "choice", h.wrap("__m_choice: { const _seq = ", "; if (_seq.len == 0) break :__m_choice @as(@TypeOf(_seq[0]), undefined); const _idx = std.crypto.random.intRangeLessThan(usize, 0, _seq.len); break :__m_choice _seq[_idx]; }", "undefined") },
    .{ "randbits", h.wrap("__m_randbits: { const _k: u6 = @intCast(", "); if (_k == 0) break :__m_randbits @as(i64, 0); const _mask: u64 = (@as(u64, 1) << _k) - 1; break :__m_randbits @as(i64, @intCast(std.crypto.random.int(u64) & _mask)); }", "0") },
    .{ "compare_digest", h.compareDigest() },
    .{ "SystemRandom", h.c("struct { pub fn random(__self: *@This()) f64 { _ = __self; const bits = std.crypto.random.int(u53); return @as(f64, @floatFromInt(bits)) / @as(f64, @floatFromInt(@as(u53, 1) << 53)); } pub fn randint(__self: *@This(), a: i64, b: i64) i64 { _ = __self; return @as(i64, @intCast(std.crypto.random.intRangeAtMost(i64, a, b))); } }{}") },
    .{ "DEFAULT_ENTROPY", h.I64(32) },
});

const nbytes_init = "const _nbytes: usize = ";
// Note: This is a static string constant, so it uses a descriptive static label
// The actual block label will be inserted by the genToken* functions
const nbytes_alloc = "; const _buf = __global_allocator.alloc(u8, _nbytes) catch break :__m_token \"\"; std.crypto.random.bytes(_buf);";

fn isNoneArg(arg: ast.Node) bool {
    return (arg == .constant and arg.constant.value == .none) or (arg == .name and std.mem.eql(u8, arg.name.id, "None"));
}
fn emitNbytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(nbytes_init);
    if (args.len > 0 and !isNoneArg(args[0])) { try self.emit("@intCast("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("32");
    try self.emit(nbytes_alloc);
}

fn genTokenBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_token: {{ ", .{id});
    try emitNbytes(self, args);
    try self.emitFmt(" break :__m{d}_token _buf; }}", .{id});
}
fn genTokenHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_token: {{ ", .{id});
    try emitNbytes(self, args);
    try self.emitFmt(" const _hex = __global_allocator.alloc(u8, _nbytes * 2) catch break :__m{d}_token \"\"; ", .{id});
    try self.emit("const _hex_chars = \"0123456789abcdef\"; for (_buf, 0..) |b, i| { _hex[i * 2] = _hex_chars[b >> 4]; _hex[i * 2 + 1] = _hex_chars[b & 0xf]; } ");
    try self.emitFmt("break :__m{d}_token _hex; }}", .{id});
}
fn genTokenUrlsafe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_token: {{ ", .{id});
    try emitNbytes(self, args);
    try self.emitFmt(" const _encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(_nbytes); const _result = __global_allocator.alloc(u8, _encoded_len) catch break :__m{d}_token \"\"; ", .{id});
    try self.emit("_ = std.base64.url_safe_no_pad.Encoder.encode(_result, _buf); ");
    try self.emitFmt("break :__m{d}_token _result; }}", .{id});
}
