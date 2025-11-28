/// Python uuid module - UUID generation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate uuid.uuid4() -> random UUID
pub fn genUuid4(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("uuid4_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _bytes: [16]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("_rand.bytes(&_bytes);\n");
    try self.emitIndent();
    try self.emit("_bytes[6] = (_bytes[6] & 0x0f) | 0x40;\n"); // version 4
    try self.emitIndent();
    try self.emit("_bytes[8] = (_bytes[8] & 0x3f) | 0x80;\n"); // variant
    try self.emitIndent();
    try self.emit("var _buf: [36]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("_ = std.fmt.bufPrint(&_buf, \"{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\", .{ _bytes[0], _bytes[1], _bytes[2], _bytes[3], _bytes[4], _bytes[5], _bytes[6], _bytes[7], _bytes[8], _bytes[9], _bytes[10], _bytes[11], _bytes[12], _bytes[13], _bytes[14], _bytes[15] }) catch break :uuid4_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :uuid4_blk &_buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate uuid.uuid1() -> time-based UUID
pub fn genUuid1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // For uuid1, use timestamp + random node
    try self.emit("uuid1_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _ts = std.time.nanoTimestamp();\n");
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(_ts));\n");
    try self.emitIndent();
    try self.emit("const _rand = _prng.random();\n");
    try self.emitIndent();
    try self.emit("var _bytes: [16]u8 = undefined;\n");
    try self.emitIndent();
    // Time bytes
    try self.emit("const _time_bytes = std.mem.asBytes(&_ts);\n");
    try self.emitIndent();
    try self.emit("@memcpy(_bytes[0..8], _time_bytes[0..8]);\n");
    try self.emitIndent();
    // Random bytes for node
    try self.emit("_rand.bytes(_bytes[8..16]);\n");
    try self.emitIndent();
    try self.emit("_bytes[6] = (_bytes[6] & 0x0f) | 0x10;\n"); // version 1
    try self.emitIndent();
    try self.emit("_bytes[8] = (_bytes[8] & 0x3f) | 0x80;\n"); // variant
    try self.emitIndent();
    try self.emit("var _buf: [36]u8 = undefined;\n");
    try self.emitIndent();
    try self.emit("_ = std.fmt.bufPrint(&_buf, \"{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}\", .{ _bytes[0], _bytes[1], _bytes[2], _bytes[3], _bytes[4], _bytes[5], _bytes[6], _bytes[7], _bytes[8], _bytes[9], _bytes[10], _bytes[11], _bytes[12], _bytes[13], _bytes[14], _bytes[15] }) catch break :uuid1_blk \"\";\n");
    try self.emitIndent();
    try self.emit("break :uuid1_blk &_buf;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate uuid.uuid3(namespace, name) -> MD5 name-based UUID
pub fn genUuid3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // UUID3 uses MD5 - placeholder returning uuid4-style
    _ = args;
    try genUuid4(self, &.{});
}

/// Generate uuid.uuid5(namespace, name) -> SHA1 name-based UUID
pub fn genUuid5(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // UUID5 uses SHA1 - placeholder returning uuid4-style
    _ = args;
    try genUuid4(self, &.{});
}

/// Generate uuid.UUID(hex=None, bytes=None, ...) -> UUID object constructor
pub fn genUUID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"00000000-0000-0000-0000-000000000000\"");
        return;
    }
    // Return the hex string argument
    try self.genExpr(args[0]);
}

/// Generate uuid.NAMESPACE_DNS constant
pub fn genNamespaceDns(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"6ba7b810-9dad-11d1-80b4-00c04fd430c8\"");
}

/// Generate uuid.NAMESPACE_URL constant
pub fn genNamespaceUrl(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"6ba7b811-9dad-11d1-80b4-00c04fd430c8\"");
}

/// Generate uuid.NAMESPACE_OID constant
pub fn genNamespaceOid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"6ba7b812-9dad-11d1-80b4-00c04fd430c8\"");
}

/// Generate uuid.NAMESPACE_X500 constant
pub fn genNamespaceX500(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"6ba7b814-9dad-11d1-80b4-00c04fd430c8\"");
}

/// Generate uuid.getnode() -> hardware address as 48-bit integer
pub fn genGetnode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a random node ID (simulated MAC address)
    try self.emit("getnode_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("var _prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));\n");
    try self.emitIndent();
    try self.emit("break :getnode_blk @as(i64, @intCast(_prng.random().int(u48)));\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}
