/// Python _sha1 module - Internal SHA1 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sha1", genConst(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }") }, .{ "update", genConst("{}") },
    .{ "digest", genConst("\"\\x00\" ** 20") }, .{ "hexdigest", genConst("\"0\" ** 40") }, .{ "copy", genConst(".{ .name = \"sha1\", .digest_size = 20, .block_size = 64 }") },
});
