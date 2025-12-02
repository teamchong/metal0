/// Python venv module - Virtual environment creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "EnvBuilder", genEnvBuilder }, .{ "create", genUnit }, .{ "ENV_CFG", genEnvCfg }, .{ "BIN_NAME", genBinName },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEnvBuilder(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .system_site_packages = false, .clear = false, .symlinks = false, .upgrade = false, .with_pip = false, .prompt = @as(?[]const u8, null), .upgrade_deps = false }"); }
fn genEnvCfg(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"pyvenv.cfg\""); }
fn genBinName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"bin\""); }
