/// Python _osx_support module - macOS platform support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "find_build_tool", genFindBuildTool },
    .{ "read_output", genReadOutput },
    .{ "find_appropriate_compiler", genFindAppropriateCompiler },
    .{ "remove_original_values", genRemoveOriginalValues },
    .{ "save_modified_value", genSaveModifiedValue },
    .{ "supports_universal_builds", genSupportsUniversalBuilds },
    .{ "find_sdk_root", genFindSdkRoot },
    .{ "get_system_version", genGetSystemVersion },
    .{ "customize_config_vars", genCustomizeConfigVars },
    .{ "customize_compiler", genCustomizeCompiler },
    .{ "get_platform_osx", genGetPlatformOsx },
});

/// Generate _osx_support._find_build_tool(toolname) - Find build tool path
pub fn genFindBuildTool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _osx_support._read_output(commandstring) - Execute and read output
pub fn genReadOutput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _osx_support._find_appropriate_compiler(config) - Find C compiler
pub fn genFindAppropriateCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _osx_support._remove_original_values(config) - Clean config
pub fn genRemoveOriginalValues(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _osx_support._save_modified_value(config, key, value) - Save value
pub fn genSaveModifiedValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _osx_support._supports_universal_builds() - Check universal support
pub fn genSupportsUniversalBuilds(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _osx_support._find_sdk_root() - Find SDK root path
pub fn genFindSdkRoot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/\"");
}

/// Generate _osx_support._get_system_version() - Get macOS version
pub fn genGetSystemVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"14.0\"");
}

/// Generate _osx_support.customize_config_vars(config) - Customize config
pub fn genCustomizeConfigVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _osx_support.customize_compiler(compiler) - Customize compiler
pub fn genCustomizeCompiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _osx_support.get_platform_osx(config, osname, release, machine) - Get platform
pub fn genGetPlatformOsx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"darwin\"");
}
