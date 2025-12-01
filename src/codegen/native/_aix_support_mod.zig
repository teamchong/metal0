/// Python _aix_support module - AIX platform support
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "aix_platform", genAixPlatform },
    .{ "aix_buildtag", genAixBuildtag },
});

/// Generate _aix_support.aix_platform() - Get AIX platform string
pub fn genAixPlatform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _aix_support.aix_buildtag() - Get AIX build tag
pub fn genAixBuildtag(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}
