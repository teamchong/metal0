/// Python _imp module - Internal import machinery support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "lock_held", genConst("false") }, .{ "acquire_lock", genConst("{}") }, .{ "release_lock", genConst("{}") },
    .{ "get_frozen_object", genConst("null") }, .{ "is_frozen", genConst("false") }, .{ "is_builtin", genConst("@as(i32, 0)") },
    .{ "is_frozen_package", genConst("false") }, .{ "create_builtin", genConst("null") }, .{ "create_dynamic", genConst("null") },
    .{ "exec_builtin", genConst("@as(i32, 0)") }, .{ "exec_dynamic", genConst("@as(i32, 0)") }, .{ "extension_suffixes", genConst("&[_][]const u8{ \".so\", \".cpython-312-darwin.so\" }") },
    .{ "source_hash", genConst("\"\\x00\" ** 8") }, .{ "check_hash_based_pycs", genConst("\"default\"") },
});
