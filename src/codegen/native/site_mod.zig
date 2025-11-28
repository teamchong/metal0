/// Python site module - Site-specific configuration hook
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// ============================================================================
// Site Configuration
// ============================================================================

/// Generate site.PREFIXES
pub fn genPREFIXES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate site.ENABLE_USER_SITE
pub fn genENABLE_USER_SITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate site.USER_SITE
pub fn genUSER_SITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

/// Generate site.USER_BASE
pub fn genUSER_BASE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?[]const u8, null)");
}

// ============================================================================
// Functions
// ============================================================================

/// Generate site.main()
pub fn genMain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate site.addsitedir(sitedir, known_paths=None)
pub fn genAddsitedir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PySet([]const u8).init()");
}

/// Generate site.getsitepackages(prefixes=None)
pub fn genGetsitepackages(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PyList([]const u8).init()");
}

/// Generate site.getuserbase()
pub fn genGetuserbase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(pyaot_allocator, \"{s}/.local\", .{home}) catch \"\"; }");
}

/// Generate site.getusersitepackages()
pub fn genGetusersitepackages(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("blk: { const home = std.posix.getenv(\"HOME\") orelse \"\"; break :blk std.fmt.allocPrint(pyaot_allocator, \"{s}/.local/lib/python3/site-packages\", .{home}) catch \"\"; }");
}

/// Generate site.removeduppaths()
pub fn genRemoveduppaths(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("pyaot_runtime.PySet([]const u8).init()");
}
