/// Python nt module - Windows NT system calls
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate nt.getcwd() - Get current working directory
pub fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate nt.getcwdb() - Get current working directory as bytes
pub fn genGetcwdb(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate nt.chdir(path) - Change directory
pub fn genChdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.listdir(path='.') - List directory
pub fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate nt.mkdir(path, mode=0o777) - Create directory
pub fn genMkdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.rmdir(path) - Remove directory
pub fn genRmdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.remove(path) - Remove file
pub fn genRemove(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.unlink(path) - Remove file
pub fn genUnlink(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.rename(src, dst) - Rename file
pub fn genRename(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.stat(path) - Get file status
pub fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }");
}

/// Generate nt.lstat(path) - Get file status without following symlinks
pub fn genLstat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }");
}

/// Generate nt.fstat(fd) - Get file status from fd
pub fn genFstat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }");
}

/// Generate nt.open(path, flags, mode=0o777) - Open file
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("-1");
}

/// Generate nt.close(fd) - Close file descriptor
pub fn genClose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.read(fd, n) - Read from file descriptor
pub fn genRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nt.write(fd, data) - Write to file descriptor
pub fn genWrite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate nt.getpid() - Get process ID
pub fn genGetpid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate nt.getppid() - Get parent process ID
pub fn genGetppid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate nt.getlogin() - Get login name
pub fn genGetlogin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nt.environ dict
pub fn genEnviron(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate nt.getenv(key, default=None) - Get environment variable
pub fn genGetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate nt.putenv(key, value) - Set environment variable
pub fn genPutenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.unsetenv(key) - Unset environment variable
pub fn genUnsetenv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate nt.access(path, mode) - Check file access
pub fn genAccess(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate nt.F_OK constant
pub fn genF_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate nt.R_OK constant
pub fn genR_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("4");
}

/// Generate nt.W_OK constant
pub fn genW_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate nt.X_OK constant
pub fn genX_OK(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate nt.O_RDONLY constant
pub fn genO_RDONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0");
}

/// Generate nt.O_WRONLY constant
pub fn genO_WRONLY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate nt.O_RDWR constant
pub fn genO_RDWR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("2");
}

/// Generate nt.O_APPEND constant
pub fn genO_APPEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("8");
}

/// Generate nt.O_CREAT constant
pub fn genO_CREAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x100");
}

/// Generate nt.O_TRUNC constant
pub fn genO_TRUNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x200");
}

/// Generate nt.O_EXCL constant
pub fn genO_EXCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x400");
}

/// Generate nt.O_BINARY constant
pub fn genO_BINARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x8000");
}

/// Generate nt.O_TEXT constant
pub fn genO_TEXT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("0x4000");
}

/// Generate nt.sep constant
pub fn genSep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\\\\"");
}

/// Generate nt.altsep constant
pub fn genAltsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"/\"");
}

/// Generate nt.extsep constant
pub fn genExtsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate nt.pathsep constant
pub fn genPathsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\";\"");
}

/// Generate nt.linesep constant
pub fn genLinesep(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\r\\n\"");
}

/// Generate nt.devnull constant
pub fn genDevnull(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"nul\"");
}

/// Generate nt.name constant
pub fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"nt\"");
}

/// Generate nt.curdir constant
pub fn genCurdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".\"");
}

/// Generate nt.pardir constant
pub fn genPardir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"..\"");
}

/// Generate nt.defpath constant
pub fn genDefpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\".;C:\\\\bin\"");
}

/// Generate nt.cpu_count() - Get CPU count
pub fn genCpuCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("1");
}

/// Generate nt.urandom(n) - Generate random bytes
pub fn genUrandom(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nt.strerror(code) - Get error string
pub fn genStrerror(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate nt.device_encoding(fd) - Get device encoding
pub fn genDeviceEncoding(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate nt.error exception
pub fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OSError");
}
