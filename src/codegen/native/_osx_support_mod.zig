/// Python _osx_support module - macOS platform support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "find_build_tool", genConst("\"\"") }, .{ "read_output", genConst("\"\"") }, .{ "find_appropriate_compiler", genConst("\"\"") },
    .{ "remove_original_values", genConst(".{}") }, .{ "save_modified_value", genConst("{}") }, .{ "supports_universal_builds", genConst("true") },
    .{ "find_sdk_root", genConst("\"/\"") }, .{ "get_system_version", genConst("\"14.0\"") }, .{ "customize_config_vars", genConst(".{}") },
    .{ "customize_compiler", genConst("{}") }, .{ "get_platform_osx", genConst("\"darwin\"") },
});
