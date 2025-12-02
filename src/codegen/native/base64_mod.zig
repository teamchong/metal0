/// Python base64 module - base64 encoding/decoding
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Public exports for dispatch/builtins.zig
pub const genB64encode = h.b64enc("standard");
pub const genB64decode = h.b64dec("standard");
pub const genUrlsafeB64encode = h.b64enc("url_safe");
pub const genUrlsafeB64decode = h.b64dec("url_safe");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "b64encode", genB64encode }, .{ "b64decode", genB64decode },
    .{ "urlsafe_b64encode", genUrlsafeB64encode }, .{ "urlsafe_b64decode", genUrlsafeB64decode },
    .{ "standard_b64encode", h.b64enc("standard") }, .{ "standard_b64decode", h.b64dec("standard") },
    .{ "encodebytes", h.b64enc("standard") }, .{ "decodebytes", h.b64dec("standard") },
    .{ "b32encode", h.stub("\"base32_not_impl\"") }, .{ "b32decode", h.stub("\"\"") },
    .{ "b16encode", genB16encode }, .{ "b16decode", genB16decode },
    .{ "a85encode", h.stub("\"a85_not_impl\"") }, .{ "a85decode", h.stub("\"\"") },
    .{ "z85encode", genZ85encode }, .{ "z85decode", genZ85decode },
});

fn genB16encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const d = "); try self.genExpr(args[0]);
    try self.emit("; const buf = __global_allocator.alloc(u8, d.len * 2) catch break :blk \"\"; _ = std.fmt.bufPrint(buf, \"{s}\", .{std.fmt.fmtSliceHexUpper(d)}) catch break :blk \"\"; break :blk buf; }");
}

fn genB16decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const d = "); try self.genExpr(args[0]);
    try self.emit("; const buf = __global_allocator.alloc(u8, d.len / 2) catch break :blk \"\"; _ = std.fmt.hexToBytes(buf, d) catch break :blk \"\"; break :blk buf; }");
}

fn genZ85encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const d = "); try self.genExpr(args[0]);
    try self.emit("; if (d.len % 4 != 0) break :blk \"\"; const z = \"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#\"; const buf = __global_allocator.alloc(u8, d.len * 5 / 4) catch break :blk \"\"; var i: usize = 0; var j: usize = 0; while (i < d.len) : ({ i += 4; j += 5; }) { var v: u32 = (@as(u32, d[i]) << 24) | (@as(u32, d[i+1]) << 16) | (@as(u32, d[i+2]) << 8) | @as(u32, d[i+3]); var k: usize = 5; while (k > 0) : (k -= 1) { buf[j + k - 1] = z[@as(usize, @intCast(v % 85))]; v /= 85; } } break :blk buf; }");
}

fn genZ85decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { const d = "); try self.genExpr(args[0]);
    try self.emit("; if (d.len % 5 != 0) break :blk \"\"; const z = \"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#\"; var dec: [256]u8 = undefined; for (z, 0..) |c, x| { dec[c] = @as(u8, @intCast(x)); } const buf = __global_allocator.alloc(u8, d.len * 4 / 5) catch break :blk \"\"; var i: usize = 0; var j: usize = 0; while (i < d.len) : ({ i += 5; j += 4; }) { var v: u32 = 0; for (0..5) |k| { v = v * 85 + @as(u32, dec[d[i + k]]); } buf[j] = @as(u8, @intCast((v >> 24) & 0xFF)); buf[j+1] = @as(u8, @intCast((v >> 16) & 0xFF)); buf[j+2] = @as(u8, @intCast((v >> 8) & 0xFF)); buf[j+3] = @as(u8, @intCast(v & 0xFF)); } break :blk buf; }");
}
