/// Python nt module - Windows NT system calls
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getcwd", genGetcwd }, .{ "getcwdb", genGetcwd }, .{ "chdir", genUnit }, .{ "listdir", genListdir },
    .{ "mkdir", genUnit }, .{ "rmdir", genUnit }, .{ "remove", genUnit }, .{ "unlink", genUnit },
    .{ "rename", genUnit }, .{ "stat", genStat }, .{ "lstat", genStat }, .{ "fstat", genStat },
    .{ "open", genNeg1 }, .{ "close", genUnit }, .{ "read", genEmptyStr }, .{ "write", genZero },
    .{ "getpid", genZero }, .{ "getppid", genZero }, .{ "getlogin", genEmptyStr }, .{ "environ", genEmpty },
    .{ "getenv", genNull }, .{ "putenv", genUnit }, .{ "unsetenv", genUnit }, .{ "access", genFalse },
    .{ "f__o_k", genZero }, .{ "r__o_k", gen4 }, .{ "w__o_k", gen2 }, .{ "x__o_k", gen1 },
    .{ "o__r_d_o_n_l_y", genZero }, .{ "o__w_r_o_n_l_y", gen1 }, .{ "o__r_d_w_r", gen2 },
    .{ "o__a_p_p_e_n_d", gen8 }, .{ "o__c_r_e_a_t", genO_CREAT }, .{ "o__t_r_u_n_c", genO_TRUNC },
    .{ "o__e_x_c_l", genO_EXCL }, .{ "o__b_i_n_a_r_y", genO_BINARY }, .{ "o__t_e_x_t", genO_TEXT },
    .{ "sep", genSep }, .{ "altsep", genAltsep }, .{ "extsep", genExtsep }, .{ "pathsep", genPathsep },
    .{ "linesep", genLinesep }, .{ "devnull", genDevnull }, .{ "name", genName },
    .{ "curdir", genCurdir }, .{ "pardir", genPardir }, .{ "defpath", genDefpath },
    .{ "cpu_count", gen1 }, .{ "urandom", genEmptyStr }, .{ "strerror", genEmptyStr },
    .{ "device_encoding", genNull }, .{ "error", genError },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }

// Common values
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn gen1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
fn gen2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn gen4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
fn gen8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "8"); }
fn genNeg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }

// Special values
fn genGetcwd(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\".\""); }
fn genListdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genStat(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }"); }
fn genO_CREAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x100"); }
fn genO_TRUNC(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x200"); }
fn genO_EXCL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x400"); }
fn genO_BINARY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8000"); }
fn genO_TEXT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x4000"); }
fn genSep(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\\\\""); }
fn genAltsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"/\""); }
fn genExtsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\".\""); }
fn genPathsep(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\";\""); }
fn genLinesep(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\r\\n\""); }
fn genDevnull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"nul\""); }
fn genName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"nt\""); }
fn genCurdir(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\".\""); }
fn genPardir(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"..\""); }
fn genDefpath(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\".;C:\\\\bin\""); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OSError"); }
