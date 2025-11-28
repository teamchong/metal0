/// Python _posixshmem module - POSIX shared memory
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _posixshmem.shm_open(name, flags, mode) - Open shared memory object
pub fn genShmOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate _posixshmem.shm_unlink(name) - Remove shared memory object
pub fn genShmUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
