/// Python _winapi module - Windows API functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _winapi.CloseHandle(handle) - Close handle
pub fn genCloseHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.CreateFile(name, access, share, security, creation, flags, template) - Create file
pub fn genCreateFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.CreateJunction(src, dst) - Create junction
pub fn genCreateJunction(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.CreateNamedPipe(name, openmode, pipemode, maxinstances, outsize, insize, timeout, security) - Create named pipe
pub fn genCreateNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.CreatePipe(security, size) - Create anonymous pipe
pub fn genCreatePipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .read = 0, .write = 0 }");
}

/// Generate _winapi.CreateProcess(app, cmd, proc_security, thread_security, inherit, flags, env, cwd, startup) - Create process
pub fn genCreateProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .process = 0, .thread = 0, .pid = 0, .tid = 0 }");
}

/// Generate _winapi.DuplicateHandle(srcproc, src, dstproc, access, inherit, options) - Duplicate handle
pub fn genDuplicateHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.ExitProcess(code) - Exit process
pub fn genExitProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.GetCurrentProcess() - Get current process handle
pub fn genGetCurrentProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate _winapi.GetExitCodeProcess(handle) - Get exit code
pub fn genGetExitCodeProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.GetLastError() - Get last error code
pub fn genGetLastError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.GetModuleFileName(module) - Get module filename
pub fn genGetModuleFileName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _winapi.GetStdHandle(handle) - Get standard handle
pub fn genGetStdHandle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.GetVersion() - Get Windows version
pub fn genGetVersion(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.OpenProcess(access, inherit, pid) - Open process
pub fn genOpenProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.PeekNamedPipe(handle, size) - Peek named pipe
pub fn genPeekNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = \"\", .available = 0, .message = 0 }");
}

/// Generate _winapi.ReadFile(handle, size, overlapped) - Read file
pub fn genReadFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = \"\", .error = 0 }");
}

/// Generate _winapi.SetNamedPipeHandleState(handle, mode, maxcollect, collecttimeout) - Set pipe state
pub fn genSetNamedPipeHandleState(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.TerminateProcess(handle, code) - Terminate process
pub fn genTerminateProcess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.WaitForMultipleObjects(handles, wait_all, ms) - Wait for multiple objects
pub fn genWaitForMultipleObjects(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.WaitForSingleObject(handle, ms) - Wait for single object
pub fn genWaitForSingleObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.WaitNamedPipe(name, ms) - Wait for named pipe
pub fn genWaitNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.WriteFile(handle, data, overlapped) - Write file
pub fn genWriteFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .written = 0, .error = 0 }");
}

/// Generate _winapi.ConnectNamedPipe(handle, overlapped) - Connect named pipe
pub fn genConnectNamedPipe(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _winapi.GetFileType(handle) - Get file type
pub fn genGetFileType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _winapi.STD_INPUT_HANDLE constant
pub fn genSTD_INPUT_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-10");
}

/// Generate _winapi.STD_OUTPUT_HANDLE constant
pub fn genSTD_OUTPUT_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-11");
}

/// Generate _winapi.STD_ERROR_HANDLE constant
pub fn genSTD_ERROR_HANDLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-12");
}

/// Generate _winapi.DUPLICATE_SAME_ACCESS constant
pub fn genDUPLICATE_SAME_ACCESS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _winapi.DUPLICATE_CLOSE_SOURCE constant
pub fn genDUPLICATE_CLOSE_SOURCE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _winapi.STARTUPINFO constant
pub fn genSTARTUPINFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _winapi.INFINITE constant
pub fn genINFINITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xFFFFFFFF");
}

/// Generate _winapi.WAIT_OBJECT_0 constant
pub fn genWAIT_OBJECT_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.WAIT_ABANDONED_0 constant
pub fn genWAIT_ABANDONED_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80");
}

/// Generate _winapi.WAIT_TIMEOUT constant
pub fn genWAIT_TIMEOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("258");
}

/// Generate _winapi.CREATE_NEW_CONSOLE constant
pub fn genCREATE_NEW_CONSOLE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x10");
}

/// Generate _winapi.CREATE_NEW_PROCESS_GROUP constant
pub fn genCREATE_NEW_PROCESS_GROUP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x200");
}

/// Generate _winapi.STILL_ACTIVE constant
pub fn genSTILL_ACTIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("259");
}

/// Generate _winapi.PIPE_ACCESS_INBOUND constant
pub fn genPIPE_ACCESS_INBOUND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate _winapi.PIPE_ACCESS_OUTBOUND constant
pub fn genPIPE_ACCESS_OUTBOUND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _winapi.PIPE_ACCESS_DUPLEX constant
pub fn genPIPE_ACCESS_DUPLEX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _winapi.NMPWAIT_WAIT_FOREVER constant
pub fn genNMPWAIT_WAIT_FOREVER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0xFFFFFFFF");
}

/// Generate _winapi.GENERIC_READ constant
pub fn genGENERIC_READ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000000");
}

/// Generate _winapi.GENERIC_WRITE constant
pub fn genGENERIC_WRITE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x40000000");
}

/// Generate _winapi.OPEN_EXISTING constant
pub fn genOPEN_EXISTING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("3");
}

/// Generate _winapi.FILE_FLAG_OVERLAPPED constant
pub fn genFILE_FLAG_OVERLAPPED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x40000000");
}

/// Generate _winapi.FILE_FLAG_FIRST_PIPE_INSTANCE constant
pub fn genFILE_FLAG_FIRST_PIPE_INSTANCE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x80000");
}

/// Generate _winapi.PIPE_WAIT constant
pub fn genPIPE_WAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate _winapi.PIPE_TYPE_MESSAGE constant
pub fn genPIPE_TYPE_MESSAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate _winapi.PIPE_READMODE_MESSAGE constant
pub fn genPIPE_READMODE_MESSAGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate _winapi.PIPE_UNLIMITED_INSTANCES constant
pub fn genPIPE_UNLIMITED_INSTANCES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("255");
}

/// Generate _winapi.ERROR_IO_PENDING constant
pub fn genERROR_IO_PENDING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("997");
}

/// Generate _winapi.ERROR_PIPE_BUSY constant
pub fn genERROR_PIPE_BUSY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("231");
}

/// Generate _winapi.ERROR_ALREADY_EXISTS constant
pub fn genERROR_ALREADY_EXISTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("183");
}

/// Generate _winapi.ERROR_BROKEN_PIPE constant
pub fn genERROR_BROKEN_PIPE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("109");
}

/// Generate _winapi.ERROR_NO_DATA constant
pub fn genERROR_NO_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("232");
}

/// Generate _winapi.ERROR_NO_SYSTEM_RESOURCES constant
pub fn genERROR_NO_SYSTEM_RESOURCES(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1450");
}

/// Generate _winapi.ERROR_OPERATION_ABORTED constant
pub fn genERROR_OPERATION_ABORTED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("995");
}

/// Generate _winapi.ERROR_PIPE_CONNECTED constant
pub fn genERROR_PIPE_CONNECTED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("535");
}

/// Generate _winapi.ERROR_SEM_TIMEOUT constant
pub fn genERROR_SEM_TIMEOUT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("121");
}

/// Generate _winapi.ERROR_MORE_DATA constant
pub fn genERROR_MORE_DATA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("234");
}

/// Generate _winapi.ERROR_NETNAME_DELETED constant
pub fn genERROR_NETNAME_DELETED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("64");
}

/// Generate _winapi.NULL constant
pub fn genNULL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}
