/// Python nt module - Windows NT system calls
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getcwd", genConst("\".\"") }, .{ "getcwdb", genConst("\".\"") }, .{ "chdir", genConst("{}") }, .{ "listdir", genConst("&[_][]const u8{}") },
    .{ "mkdir", genConst("{}") }, .{ "rmdir", genConst("{}") }, .{ "remove", genConst("{}") }, .{ "unlink", genConst("{}") },
    .{ "rename", genConst("{}") }, .{ "stat", genConst(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "lstat", genConst(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") }, .{ "fstat", genConst(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "open", genConst("-1") }, .{ "close", genConst("{}") }, .{ "read", genConst("\"\"") }, .{ "write", genConst("0") },
    .{ "getpid", genConst("0") }, .{ "getppid", genConst("0") }, .{ "getlogin", genConst("\"\"") }, .{ "environ", genConst(".{}") },
    .{ "getenv", genConst("null") }, .{ "putenv", genConst("{}") }, .{ "unsetenv", genConst("{}") }, .{ "access", genConst("false") },
    .{ "f__o_k", genConst("0") }, .{ "r__o_k", genConst("4") }, .{ "w__o_k", genConst("2") }, .{ "x__o_k", genConst("1") },
    .{ "o__r_d_o_n_l_y", genConst("0") }, .{ "o__w_r_o_n_l_y", genConst("1") }, .{ "o__r_d_w_r", genConst("2") },
    .{ "o__a_p_p_e_n_d", genConst("8") }, .{ "o__c_r_e_a_t", genConst("0x100") }, .{ "o__t_r_u_n_c", genConst("0x200") },
    .{ "o__e_x_c_l", genConst("0x400") }, .{ "o__b_i_n_a_r_y", genConst("0x8000") }, .{ "o__t_e_x_t", genConst("0x4000") },
    .{ "sep", genConst("\"\\\\\"") }, .{ "altsep", genConst("\"/\"") }, .{ "extsep", genConst("\".\"") }, .{ "pathsep", genConst("\";\"") },
    .{ "linesep", genConst("\"\\r\\n\"") }, .{ "devnull", genConst("\"nul\"") }, .{ "name", genConst("\"nt\"") },
    .{ "curdir", genConst("\".\"") }, .{ "pardir", genConst("\"..\"") }, .{ "defpath", genConst("\".;C:\\\\bin\"") },
    .{ "cpu_count", genConst("1") }, .{ "urandom", genConst("\"\"") }, .{ "strerror", genConst("\"\"") },
    .{ "device_encoding", genConst("null") }, .{ "error", genConst("error.OSError") },
});
