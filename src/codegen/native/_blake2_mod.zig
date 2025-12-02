/// Python _blake2 module - BLAKE2 hash functions (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "blake2b", genConst(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }") },
    .{ "blake2s", genConst(".{ .name = \"blake2s\", .digest_size = 32, .block_size = 64 }") },
    .{ "update", genConst("{}") }, .{ "digest", genConst("\"\"") }, .{ "hexdigest", genConst("\"0\" ** 128") },
    .{ "copy", genConst(".{ .name = \"blake2b\", .digest_size = 64, .block_size = 128 }") },
    .{ "BLAKE2B_SALT_SIZE", genConst("@as(u32, 16)") }, .{ "BLAKE2B_PERSON_SIZE", genConst("@as(u32, 16)") },
    .{ "BLAKE2B_MAX_KEY_SIZE", genConst("@as(u32, 64)") }, .{ "BLAKE2B_MAX_DIGEST_SIZE", genConst("@as(u32, 64)") },
    .{ "BLAKE2S_SALT_SIZE", genConst("@as(u32, 8)") }, .{ "BLAKE2S_PERSON_SIZE", genConst("@as(u32, 8)") },
    .{ "BLAKE2S_MAX_KEY_SIZE", genConst("@as(u32, 32)") }, .{ "BLAKE2S_MAX_DIGEST_SIZE", genConst("@as(u32, 32)") },
});
