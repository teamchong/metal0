/// Python venv module - Virtual environment creation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate venv.EnvBuilder(system_site_packages=False, clear=False, symlinks=False, upgrade=False, with_pip=False, prompt=None, upgrade_deps=False)
pub fn genEnvBuilder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .system_site_packages = false, .clear = false, .symlinks = false, .upgrade = false, .with_pip = false, .prompt = @as(?[]const u8, null), .upgrade_deps = false }");
}

/// Generate venv.create(env_dir, system_site_packages=False, clear=False, symlinks=False, with_pip=False, prompt=None, upgrade_deps=False)
pub fn genCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

// ============================================================================
// Constants
// ============================================================================

pub fn genENV_CFG(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"pyvenv.cfg\"");
}

pub fn genBIN_NAME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Platform dependent
    try self.emit("\"bin\"");
}
