/// Python nis module - NIS (Yellow Pages) interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "match", genConst("\"\"") }, .{ "cat", genConst(".{}") },
    .{ "maps", genConst("&[_][]const u8{}") }, .{ "get_default_domain", genConst("\"\"") },
    .{ "error", genConst("error.NisError") },
});
