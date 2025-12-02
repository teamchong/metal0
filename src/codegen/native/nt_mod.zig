/// Python nt module - Windows NT system calls
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\".\""); }
fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OSError"); }
fn genInt(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("{}", .{n})); } }.f;
}
fn genHex(comptime v: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, v); } }.f;
}
fn genStr(comptime s: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"" ++ s ++ "\""); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getcwd", genGetcwd }, .{ "getcwdb", genGetcwd }, .{ "chdir", genUnit }, .{ "listdir", genListdir },
    .{ "mkdir", genUnit }, .{ "rmdir", genUnit }, .{ "remove", genUnit }, .{ "unlink", genUnit },
    .{ "rename", genUnit }, .{ "stat", genStat }, .{ "lstat", genStat }, .{ "fstat", genStat },
    .{ "open", genInt(-1) }, .{ "close", genUnit }, .{ "read", genEmptyStr }, .{ "write", genInt(0) },
    .{ "getpid", genInt(0) }, .{ "getppid", genInt(0) }, .{ "getlogin", genEmptyStr }, .{ "environ", genEmpty },
    .{ "getenv", genNull }, .{ "putenv", genUnit }, .{ "unsetenv", genUnit }, .{ "access", genFalse },
    .{ "f__o_k", genInt(0) }, .{ "r__o_k", genInt(4) }, .{ "w__o_k", genInt(2) }, .{ "x__o_k", genInt(1) },
    .{ "o__r_d_o_n_l_y", genInt(0) }, .{ "o__w_r_o_n_l_y", genInt(1) }, .{ "o__r_d_w_r", genInt(2) },
    .{ "o__a_p_p_e_n_d", genInt(8) }, .{ "o__c_r_e_a_t", genHex("0x100") }, .{ "o__t_r_u_n_c", genHex("0x200") },
    .{ "o__e_x_c_l", genHex("0x400") }, .{ "o__b_i_n_a_r_y", genHex("0x8000") }, .{ "o__t_e_x_t", genHex("0x4000") },
    .{ "sep", genStr("\\\\") }, .{ "altsep", genStr("/") }, .{ "extsep", genStr(".") }, .{ "pathsep", genStr(";") },
    .{ "linesep", genStr("\\r\\n") }, .{ "devnull", genStr("nul") }, .{ "name", genStr("nt") },
    .{ "curdir", genStr(".") }, .{ "pardir", genStr("..") }, .{ "defpath", genStr(".;C:\\\\bin") },
    .{ "cpu_count", genInt(1) }, .{ "urandom", genEmptyStr }, .{ "strerror", genEmptyStr },
    .{ "device_encoding", genNull }, .{ "error", genError },
});
