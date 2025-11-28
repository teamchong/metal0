/// Python pty module - Pseudo-terminal utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pty.fork()
/// Returns (pid, fd) - fork and connect to pty
pub fn genFork(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, -1), @as(i32, -1) }");
}

/// Generate pty.openpty()
/// Returns (master_fd, slave_fd) - open a pty pair
pub fn genOpenpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, -1), @as(i32, -1) }");
}

/// Generate pty.spawn(argv, master_read=None, stdin_read=None)
/// Spawn a process and connect to pty
pub fn genSpawn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate pty.STDIN_FILENO
pub fn genSTDIN_FILENO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate pty.STDOUT_FILENO
pub fn genSTDOUT_FILENO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate pty.STDERR_FILENO
pub fn genSTDERR_FILENO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate pty.CHILD
pub fn genCHILD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}
