/// Python uuid module - UUID generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");

const UuidFmt = "\"{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"";
const UuidBytesArgs = ", .{ _bytes[0], _bytes[1], _bytes[2], _bytes[3], _bytes[4], _bytes[5], _bytes[6], _bytes[7], _bytes[8], _bytes[9], _bytes[10], _bytes[11], _bytes[12], _bytes[13], _bytes[14], _bytes[15] })";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "uuid4", genUuid4 }, .{ "uuid1", genUuid1 }, .{ "uuid3", genUuid4 }, .{ "uuid5", genUuid4 },
    .{ "UUID", h.pass("\"00000000-0000-0000-0000-000000000000\"") },
    .{ "NAMESPACE_DNS", h.c("\"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_URL", h.c("\"6ba7b811-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_OID", h.c("\"6ba7b812-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "NAMESPACE_X500", h.c("\"6ba7b814-9dad-11d1-80b4-00c04fd430c8\"") },
    .{ "getnode", genGetnode },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genUuid4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("uuid4", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try c.emitFmt("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp())); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; _rand.bytes(&_bytes); _bytes[6] = (_bytes[6] & 0x0f) | 0x40; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, {s}{s} catch break :{s} \"\"; break :{s} &_buf", .{ UuidFmt, UuidBytesArgs, label, label });
        }
    }.emit);
}

fn genUuid1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.withInlineBlock("uuid1", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, _: []ast.Node) !void {
            try c.emitFmt("const _ts = std.time.nanoTimestamp(); var _prng = std.Random.DefaultPrng.init(@intCast(_ts)); const _rand = _prng.random(); var _bytes: [16]u8 = undefined; const _time_bytes = std.mem.asBytes(&_ts); @memcpy(_bytes[0..8], _time_bytes[0..8]); _rand.bytes(_bytes[8..16]); _bytes[6] = (_bytes[6] & 0x0f) | 0x10; _bytes[8] = (_bytes[8] & 0x3f) | 0x80; var _buf: [36]u8 = undefined; _ = std.fmt.bufPrint(&_buf, {s}{s} catch break :{s} \"\"; break :{s} &_buf", .{ UuidFmt, UuidBytesArgs, label, label });
        }
    }.emit);
}

fn genGetnode(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.emitInlineBlockRaw("gn", "var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));", "@as(i64, @intCast(_prng.random().int(u48)))");
}
