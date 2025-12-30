/// Python nt module - Windows NT system calls
/// MIGRATED TO ZIGBUILDER
/// DRY: Uses h.c(), h.I64() factories for constants
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // File/directory operations (stub implementations)
    .{ "getcwd", h.c("\".\"") },
    .{ "getcwdb", h.c("\".\"") },
    .{ "chdir", h.c("{}") },
    .{ "listdir", h.c("&[_][]const u8{}") },
    .{ "mkdir", h.c("{}") },
    .{ "rmdir", h.c("{}") },
    .{ "remove", h.c("{}") },
    .{ "unlink", h.c("{}") },
    .{ "rename", h.c("{}") },
    .{ "stat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "lstat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "fstat", h.c(".{ .st_mode = 0, .st_size = 0, .st_mtime = 0 }") },
    .{ "open", h.I64(-1) },
    .{ "close", h.c("{}") },
    .{ "read", h.c("\"\"") },
    .{ "write", h.I64(0) },
    // Process operations
    .{ "getpid", h.I64(0) },
    .{ "getppid", h.I64(0) },
    .{ "getlogin", h.c("\"\"") },
    // Environment operations
    .{ "environ", h.c(".{}") },
    .{ "getenv", h.c("null") },
    .{ "putenv", h.c("{}") },
    .{ "unsetenv", h.c("{}") },
    // Access check
    .{ "access", h.c("false") },
    // Access mode constants
    .{ "f__o_k", h.I64(0) },
    .{ "r__o_k", h.I64(4) },
    .{ "w__o_k", h.I64(2) },
    .{ "x__o_k", h.I64(1) },
    // Open mode constants
    .{ "o__r_d_o_n_l_y", h.I64(0) },
    .{ "o__w_r_o_n_l_y", h.I64(1) },
    .{ "o__r_d_w_r", h.I64(2) },
    .{ "o__a_p_p_e_n_d", h.I64(8) },
    .{ "o__c_r_e_a_t", h.I64(0x100) },
    .{ "o__t_r_u_n_c", h.I64(0x200) },
    .{ "o__e_x_c_l", h.I64(0x400) },
    .{ "o__b_i_n_a_r_y", h.I64(0x8000) },
    .{ "o__t_e_x_t", h.I64(0x4000) },
    // Path constants (Windows-specific)
    .{ "sep", h.c("\"\\\\\"") },
    .{ "altsep", h.c("\"/\"") },
    .{ "extsep", h.c("\".\"") },
    .{ "pathsep", h.c("\";\"") },
    .{ "linesep", h.c("\"\\r\\n\"") },
    .{ "devnull", h.c("\"nul\"") },
    .{ "name", h.c("\"nt\"") },
    .{ "curdir", h.c("\".\"") },
    .{ "pardir", h.c("\"..\"") },
    .{ "defpath", h.c("\".;C:\\\\bin\"") },
    // System info
    .{ "cpu_count", h.I64(1) },
    .{ "urandom", h.c("\"\"") },
    .{ "strerror", h.c("\"\"") },
    .{ "device_encoding", h.c("null") },
    // Error type
    .{ "error", h.err("OSError") },
});
