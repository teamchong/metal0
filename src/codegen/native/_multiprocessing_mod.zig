/// Python _multiprocessing module - Internal multiprocessing support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "sem_lock", genSemLock }, .{ "sem_unlink", genUnit }, .{ "address_of_buffer", genAddrBuf },
    .{ "flags", genFlags }, .{ "connection", genConn }, .{ "send", genUnit }, .{ "recv", genNull },
    .{ "poll", genFalse }, .{ "send_bytes", genUnit }, .{ "recv_bytes", genEmptyStr },
    .{ "recv_bytes_into", genUSize0 }, .{ "close", genUnit }, .{ "fileno", genI32N1 },
    .{ "acquire", genTrue }, .{ "release", genUnit }, .{ "count", genI32_0 }, .{ "is_mine", genFalse },
    .{ "get_value", genI32_1 }, .{ "is_zero", genFalse }, .{ "rebuild", genSemLock },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32N1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, -1)"); }
fn genUSize0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(usize, 0)"); }
fn genSemLock(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .kind = 0, .value = 1, .maxvalue = 1, .name = \"\" }"); }
fn genAddrBuf(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(usize, 0), @as(usize, 0) }"); }
fn genFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .HAVE_SEM_OPEN = true, .HAVE_SEM_TIMEDWAIT = true, .HAVE_FD_TRANSFER = true, .HAVE_BROKEN_SEM_GETVALUE = false }"); }
fn genConn(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .handle = null, .readable = true, .writable = true }"); }
