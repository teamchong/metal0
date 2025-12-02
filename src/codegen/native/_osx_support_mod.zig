/// Python _osx_support module - macOS platform support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genRoot(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"/\""); }
fn genVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"14.0\""); }
fn genDarwin(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"darwin\""); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "find_build_tool", genEmptyStr }, .{ "read_output", genEmptyStr }, .{ "find_appropriate_compiler", genEmptyStr },
    .{ "remove_original_values", genEmpty }, .{ "save_modified_value", genUnit }, .{ "supports_universal_builds", genTrue },
    .{ "find_sdk_root", genRoot }, .{ "get_system_version", genVersion }, .{ "customize_config_vars", genEmpty },
    .{ "customize_compiler", genUnit }, .{ "get_platform_osx", genDarwin },
});
