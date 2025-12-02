/// Python linecache module - Random access to text lines
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getline", genConst("\"\"") }, .{ "getlines", genConst("&[_][]const u8{}") },
    .{ "clearcache", genConst("{}") }, .{ "checkcache", genConst("{}") },
    .{ "updatecache", genConst("&[_][]const u8{}") }, .{ "lazycache", genConst("false") },
    .{ "cache", genConst("hashmap_helper.StringHashMap([][]const u8).init(__global_allocator)") },
});
