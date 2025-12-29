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

const ZigBuilder = builder_mod.ZigBuilder;
const ZigValue = builder_mod.ZigValue;

fn genUuid4(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.withLabeledBlock("__uuid4", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, _: void) !void {
            try bld.emitVarRaw("_prng", null, "std.Random.DefaultPrng.init(@intCast(std.time.timestamp()))");
            try bld.emitConstRaw("_rand", "_prng.random()");
            try bld.emitVarRaw("_bytes", "[16]u8", "undefined");
            try bld.emitRawLine("_rand.bytes(&_bytes);");
            try bld.emitRawLine("_bytes[6] = (_bytes[6] & 0x0f) | 0x40;");
            try bld.emitRawLine("_bytes[8] = (_bytes[8] & 0x3f) | 0x80;");
            try bld.emitVarRaw("_buf", "[36]u8", "undefined");
            try bld.emitRawLine("_ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidBytesArgs ++ " catch break :__uuid4 \"\";");
            try scope.breakWithRaw("&_buf");
        }
    }.emit, {});
    try self.flushBuilder();
}

fn genUuid1(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.withLabeledBlock("__uuid1", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, _: void) !void {
            try bld.emitConstRaw("_ts", "std.time.nanoTimestamp()");
            try bld.emitVarRaw("_prng", null, "std.Random.DefaultPrng.init(@intCast(_ts))");
            try bld.emitConstRaw("_rand", "_prng.random()");
            try bld.emitVarRaw("_bytes", "[16]u8", "undefined");
            try bld.emitConstRaw("_time_bytes", "std.mem.asBytes(&_ts)");
            try bld.emitRawLine("@memcpy(_bytes[0..8], _time_bytes[0..8]);");
            try bld.emitRawLine("_rand.bytes(_bytes[8..16]);");
            try bld.emitRawLine("_bytes[6] = (_bytes[6] & 0x0f) | 0x10;");
            try bld.emitRawLine("_bytes[8] = (_bytes[8] & 0x3f) | 0x80;");
            try bld.emitVarRaw("_buf", "[36]u8", "undefined");
            try bld.emitRawLine("_ = std.fmt.bufPrint(&_buf, " ++ UuidFmt ++ UuidBytesArgs ++ " catch break :__uuid1 \"\";");
            try scope.breakWithRaw("&_buf");
        }
    }.emit, {});
    try self.flushBuilder();
}

fn genGetnode(self: *NativeCodegen, _: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.withLabeledBlock("__gn", struct {
        fn emit(bld: *ZigBuilder, scope: *ZigBuilder.LabeledBlockScope, _: void) !void {
            try bld.emitVarRaw("_prng", null, "std.Random.DefaultPrng.init(@intCast(std.time.timestamp()))");
            try scope.breakWithRaw("@as(i64, @intCast(_prng.random().int(u48)))");
        }
    }.emit, {});
    try self.flushBuilder();
}
