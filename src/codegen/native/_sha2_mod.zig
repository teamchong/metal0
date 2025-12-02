/// Python _sha2 module - Internal SHA2 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha224", genConst(".{ .name = \"sha224\", .digest_size = 28, .block_size = 64 }") }, .{ "sha256", genConst(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }") },
    .{ "sha384", genConst(".{ .name = \"sha384\", .digest_size = 48, .block_size = 128 }") }, .{ "sha512", genConst(".{ .name = \"sha512\", .digest_size = 64, .block_size = 128 }") },
    .{ "update", genConst("{}") }, .{ "digest", genConst("\"\\x00\" ** 32") }, .{ "hexdigest", genConst("\"0\" ** 64") }, .{ "copy", genConst(".{ .name = \"sha256\", .digest_size = 32, .block_size = 64 }") },
});
