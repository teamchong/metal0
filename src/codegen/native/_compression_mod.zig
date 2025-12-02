/// Python _compression module - Internal compression support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "DecompressReader", genConst(".{ .fp = null, .decomp = null, .eof = false, .pos = 0, .size = -1 }") }, .{ "BaseStream", genConst(".{}") },
    .{ "readable", genConst("true") }, .{ "writable", genConst("false") }, .{ "seekable", genConst("true") },
    .{ "read", genConst("\"\"") }, .{ "read1", genConst("\"\"") }, .{ "readline", genConst("\"\"") },
    .{ "readlines", genConst("&[_][]const u8{}") }, .{ "readinto", genConst("@as(usize, 0)") },
    .{ "seek", genConst("@as(i64, 0)") }, .{ "tell", genConst("@as(i64, 0)") }, .{ "close", genConst("{}") },
});
