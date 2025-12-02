/// Python base64 module - base64 encoding/decoding
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "b64encode", genB64encode }, .{ "b64decode", genB64decode },
    .{ "urlsafe_b64encode", genUrlsafeB64encode }, .{ "urlsafe_b64decode", genUrlsafeB64decode },
    .{ "standard_b64encode", genB64encode }, .{ "standard_b64decode", genB64decode },
    .{ "encodebytes", genB64encode }, .{ "decodebytes", genB64decode },
    .{ "b32encode", genB32encode }, .{ "b32decode", genB32decode },
    .{ "b16encode", genB16encode }, .{ "b16decode", genB16decode },
    .{ "a85encode", genA85encode }, .{ "a85decode", genA85decode },
    .{ "z85encode", genZ85encode }, .{ "z85decode", genZ85decode },
});

fn genEncHelper(comptime encoder: []const u8) h.H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) return;
            try self.emit("blk: { const d = "); try self.genExpr(args[0]);
            try self.emit("; const len = std.base64." ++ encoder ++ ".Encoder.calcSize(d.len); const buf = __global_allocator.alloc(u8, len) catch break :blk \"\"; break :blk std.base64." ++ encoder ++ ".Encoder.encode(buf, d); }");
        }
    }.f;
}

fn genDecHelper(comptime decoder: []const u8) h.H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) return;
            try self.emit("blk: { const d = "); try self.genExpr(args[0]);
            try self.emit("; const len = std.base64." ++ decoder ++ ".Decoder.calcSizeForSlice(d) catch break :blk \"\"; const buf = __global_allocator.alloc(u8, len) catch break :blk \"\"; std.base64." ++ decoder ++ ".Decoder.decode(buf, d) catch break :blk \"\"; break :blk buf; }");
        }
    }.f;
}

fn genStub(self: *NativeCodegen, args: []ast.Node, result: []const u8) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk "); try self.emit(result); try self.emit("; }");
}

pub const genB64encode = genEncHelper("standard");
pub const genB64decode = genDecHelper("standard");
pub const genUrlsafeB64encode = genEncHelper("url_safe");
pub const genUrlsafeB64decode = genDecHelper("url_safe");
fn genB32encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genStub(self, args, "\"base32_not_impl\""); }
fn genB32decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genStub(self, args, "\"\""); }
fn genA85encode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genStub(self, args, "\"a85_not_impl\""); }
fn genA85decode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genStub(self, args, "\"\""); }

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
