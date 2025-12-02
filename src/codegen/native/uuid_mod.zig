/// Python uuid module - UUID generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "uuid4", genUuid4 }, .{ "uuid1", genUuid1 }, .{ "uuid3", genUuid4 }, .{ "uuid5", genUuid4 },
    .{ "UUID", genUUID }, .{ "NAMESPACE_DNS", genNsDns }, .{ "NAMESPACE_URL", genNsUrl },
    .{ "NAMESPACE_OID", genNsOid }, .{ "NAMESPACE_X500", genNsX500 }, .{ "getnode", genGetnode },
});

const UuidFmt = "\"{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"";
const UuidArgs = ", .{ _bytes[0], _bytes[1], _bytes[2], _bytes[3], _bytes[4], _bytes[5], _bytes[6], _bytes[7], _bytes[8], _bytes[9], _bytes[10], _bytes[11], _bytes[12], _bytes[13], _bytes[14], _bytes[15] }) catch break :blk \"\"; break :blk &_buf; }";

fn genUuid4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; _rand.bytes(&_bytes); _bytes[6] = (_bytes[6] & 0x0f) | 0x40; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidArgs);
}

fn genUuid1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { const _ts = std.time.nanoTimestamp(); var _prng = std.Random.DefaultPrng.init(@intCast(_ts)); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; const _time_bytes = std.mem.asBytes(&_ts); @memcpy(_bytes[0..8], _time_bytes[0..8]); _rand.bytes(_bytes[8..16]); _bytes[6] = (_bytes[6] & 0x0f) | 0x10; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidArgs);
}

fn genUUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("\"00000000-0000-0000-0000-000000000000\""); return; }
    try self.genExpr(args[0]);
}

fn genNsDns(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"6ba7b810-9dad-11d1-80b4-00c04fd430c8\""); }
fn genNsUrl(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"6ba7b811-9dad-11d1-80b4-00c04fd430c8\""); }
fn genNsOid(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"6ba7b812-9dad-11d1-80b4-00c04fd430c8\""); }
fn genNsX500(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"6ba7b814-9dad-11d1-80b4-00c04fd430c8\""); }
fn genGetnode(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("blk: { var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); break :blk @as(i64, @intCast(_prng.random().int(u48))); }"); }
