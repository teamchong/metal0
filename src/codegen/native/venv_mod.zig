/// Python venv module - Virtual environment creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "EnvBuilder", genConst(".{ .system_site_packages = false, .clear = false, .symlinks = false, .upgrade = false, .with_pip = false, .prompt = @as(?[]const u8, null), .upgrade_deps = false }") },
    .{ "create", genConst("{}") },
    .{ "ENV_CFG", genConst("\"pyvenv.cfg\"") },
    .{ "BIN_NAME", genConst("\"bin\"") },
});
