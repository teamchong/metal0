/// Python _sha3 module - Internal SHA3 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha3_224", genConst(".{ .name = \"sha3_224\", .digest_size = 28, .block_size = 144 }") }, .{ "sha3_256", genConst(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }") },
    .{ "sha3_384", genConst(".{ .name = \"sha3_384\", .digest_size = 48, .block_size = 104 }") }, .{ "sha3_512", genConst(".{ .name = \"sha3_512\", .digest_size = 64, .block_size = 72 }") },
    .{ "shake128", genConst(".{ .name = \"shake_128\", .digest_size = 0, .block_size = 168 }") }, .{ "shake256", genConst(".{ .name = \"shake_256\", .digest_size = 0, .block_size = 136 }") },
    .{ "update", genConst("{}") }, .{ "digest", genConst("\"\\x00\" ** 32") }, .{ "hexdigest", genConst("\"0\" ** 64") }, .{ "copy", genConst(".{ .name = \"sha3_256\", .digest_size = 32, .block_size = 136 }") },
    .{ "shake_digest", genConst("\"\"") }, .{ "shake_hexdigest", genConst("\"\"") },
});
