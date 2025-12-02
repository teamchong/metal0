/// Python nt module - Windows NT system calls
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getcwd", h.c("\".\"") }, .{ "getcwdb", h.c("\".\"") }, .{ "chdir", h.c("{}") }, .{ "listdir", h.c("&[_][]const u8{}") },
    .{ "mkdir", h.c("{}") }, .{ "rmdir", h.c("{}") }, .{ "remove", h.c("{}") }, .{ "unlink", h.c("{}") },
    .{ "rename", h.c("{}") }, .{ "stat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "lstat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") }, .{ "fstat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "open", h.c("-1") }, .{ "close", h.c("{}") }, .{ "read", h.c("\"\"") }, .{ "write", h.c("0") },
    .{ "getpid", h.c("0") }, .{ "getppid", h.c("0") }, .{ "getlogin", h.c("\"\"") }, .{ "environ", h.c(".{}") },
    .{ "getenv", h.c("null") }, .{ "putenv", h.c("{}") }, .{ "unsetenv", h.c("{}") }, .{ "access", h.c("false") },
    .{ "f__o_k", h.c("0") }, .{ "r__o_k", h.c("4") }, .{ "w__o_k", h.c("2") }, .{ "x__o_k", h.c("1") },
    .{ "o__r_d_o_n_l_y", h.c("0") }, .{ "o__w_r_o_n_l_y", h.c("1") }, .{ "o__r_d_w_r", h.c("2") },
    .{ "o__a_p_p_e_n_d", h.c("8") }, .{ "o__c_r_e_a_t", h.c("0x100") }, .{ "o__t_r_u_n_c", h.c("0x200") },
    .{ "o__e_x_c_l", h.c("0x400") }, .{ "o__b_i_n_a_r_y", h.c("0x8000") }, .{ "o__t_e_x_t", h.c("0x4000") },
    .{ "sep", h.c("\"\\\\\"") }, .{ "altsep", h.c("\"/\"") }, .{ "extsep", h.c("\".\"") }, .{ "pathsep", h.c("\";\"") },
    .{ "linesep", h.c("\"\\r\\n\"") }, .{ "devnull", h.c("\"nul\"") }, .{ "name", h.c("\"nt\"") },
    .{ "curdir", h.c("\".\"") }, .{ "pardir", h.c("\"..\"") }, .{ "defpath", h.c("\".;C:\\\\bin\"") },
    .{ "cpu_count", h.c("1") }, .{ "urandom", h.c("\"\"") }, .{ "strerror", h.c("\"\"") },
    .{ "device_encoding", h.c("null") }, .{ "error", h.err("OSError") },
});
