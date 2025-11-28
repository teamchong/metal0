/// Python _multiprocessing module - Internal multiprocessing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _multiprocessing.SemLock(kind, value, maxvalue, name, unlink)
pub fn genSemLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }");
}

/// Generate _multiprocessing.sem_unlink(name)
pub fn genSemUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _multiprocessing.address_of_buffer(obj)
pub fn genAddressOfBuffer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(usize, 0), @as(usize, 0) }");
}

/// Generate _multiprocessing.flags dict
pub fn genFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .HAVE_SEM_OPEN = true, .HAVE_SEM_TIMEDWAIT = true, .HAVE_FD_TRANSFER = true, .HAVE_BROKEN_SEM_GETVALUE = false }");
}

/// Generate _multiprocessing.Connection class
pub fn genConnection(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .handle = null, .readable = true, .writable = true }");
}

/// Generate Connection.send(obj)
pub fn genSend(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.recv()
pub fn genRecv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate Connection.poll(timeout=0.0)
pub fn genPoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate Connection.send_bytes(data, offset=0, size=None)
pub fn genSendBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.recv_bytes(maxlength=None)
pub fn genRecvBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate Connection.recv_bytes_into(buffer, offset=0)
pub fn genRecvBytesInto(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(usize, 0)");
}

/// Generate Connection.close()
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Connection.fileno()
pub fn genFileno(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, -1)");
}

/// Generate SemLock.acquire(block=True, timeout=None)
pub fn genAcquire(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate SemLock.release()
pub fn genRelease(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate SemLock._count()
pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate SemLock._is_mine()
pub fn genIsMine(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SemLock._get_value()
pub fn genGetValue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate SemLock._is_zero()
pub fn genIsZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate SemLock._rebuild(handle, kind, maxvalue, name)
pub fn genRebuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }");
}
