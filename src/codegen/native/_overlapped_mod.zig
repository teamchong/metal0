/// Python _overlapped module - Windows overlapped I/O
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _overlapped.Overlapped(event=None) - Create overlapped I/O object
pub fn genOverlapped(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _overlapped.CreateEvent(security, manual_reset, initial_state, name) - Create event
pub fn genCreateEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _overlapped.CreateIoCompletionPort(handle, port, key, concurrency) - Create IOCP
pub fn genCreateIoCompletionPort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _overlapped.GetQueuedCompletionStatus(port, ms) - Get completion status
pub fn genGetQueuedCompletionStatus(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .bytes = 0, .key = 0, .overlapped = null }");
}

/// Generate _overlapped.PostQueuedCompletionStatus(port, bytes, key, overlapped) - Post status
pub fn genPostQueuedCompletionStatus(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.ResetEvent(handle) - Reset event
pub fn genResetEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.SetEvent(handle) - Set event
pub fn genSetEvent(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.FormatMessage(error_code) - Format error message
pub fn genFormatMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _overlapped.BindLocal(socket, family) - Bind socket locally
pub fn genBindLocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.RegisterWaitWithQueue(object, port, key, ms) - Register wait
pub fn genRegisterWaitWithQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _overlapped.UnregisterWait(wait_handle) - Unregister wait
pub fn genUnregisterWait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.UnregisterWaitEx(wait_handle, event) - Unregister wait with event
pub fn genUnregisterWaitEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _overlapped.ConnectPipe(handle) - Connect named pipe
pub fn genConnectPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _overlapped.WSAConnect(socket, address) - WSA connect
pub fn genWSAConnect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _overlapped.INVALID_HANDLE_VALUE constant
pub fn genINVALID_HANDLE_VALUE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate _overlapped.NULL constant
pub fn genNULL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _overlapped.ERROR_IO_PENDING constant
pub fn genERROR_IO_PENDING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("997");
}

/// Generate _overlapped.ERROR_NETNAME_DELETED constant
pub fn genERROR_NETNAME_DELETED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("64");
}

/// Generate _overlapped.ERROR_SEM_TIMEOUT constant
pub fn genERROR_SEM_TIMEOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("121");
}

/// Generate _overlapped.ERROR_PIPE_BUSY constant
pub fn genERROR_PIPE_BUSY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("231");
}

/// Generate _overlapped.INFINITE constant
pub fn genINFINITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xFFFFFFFF");
}
