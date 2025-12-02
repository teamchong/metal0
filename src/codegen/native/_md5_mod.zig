/// Python _md5 module - Internal MD5 support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "md5", genConst(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }") }, .{ "update", genConst("{}") },
    .{ "digest", genConst("\"\\x00\" ** 16") }, .{ "hexdigest", genConst("\"0\" ** 32") }, .{ "copy", genConst(".{ .name = \"md5\", .digest_size = 16, .block_size = 64 }") },
});
