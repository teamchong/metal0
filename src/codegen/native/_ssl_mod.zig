/// Python _ssl module - Internal SSL support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "s_s_l_context", h.c(".{ .protocol = 2, .verify_mode = 0, .check_hostname = false }") },
    .{ "s_s_l_socket", h.c(".{ .context = null, .server_side = false, .server_hostname = null }") },
    .{ "memory_b_i_o", h.c(".{ .pending = 0, .eof = false }") },
    .{ "r_a_n_d_status", h.c("true") }, .{ "r_a_n_d_add", h.c("{}") }, .{ "r_a_n_d_bytes", h.c("\"\"") },
    .{ "r_a_n_d_pseudo_bytes", h.c(".{ \"\", true }") },
    .{ "txt2obj", h.c(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }") },
    .{ "nid2obj", h.c(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }") },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n", h.c("\"OpenSSL 3.0.0 0 Jan 2024\"") },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__n_u_m_b_e_r", h.I64(0x30000000) },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__i_n_f_o", h.c(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "p_r_o_t_o_c_o_l__s_s_lv23", h.I32(2) }, .{ "p_r_o_t_o_c_o_l__t_l_s", h.I32(2) },
    .{ "p_r_o_t_o_c_o_l__t_l_s__c_l_i_e_n_t", h.I32(16) }, .{ "p_r_o_t_o_c_o_l__t_l_s__s_e_r_v_e_r", h.I32(17) },
    .{ "c_e_r_t__n_o_n_e", h.I32(0) }, .{ "c_e_r_t__o_p_t_i_o_n_a_l", h.I32(1) }, .{ "c_e_r_t__r_e_q_u_i_r_e_d", h.I32(2) },
    .{ "h_a_s__s_n_i", h.c("true") }, .{ "h_a_s__e_c_d_h", h.c("true") }, .{ "h_a_s__n_p_n", h.c("false") }, .{ "h_a_s__a_l_p_n", h.c("true") },
    .{ "h_a_s__t_l_sv1", h.c("true") }, .{ "h_a_s__t_l_sv1_1", h.c("true") }, .{ "h_a_s__t_l_sv1_2", h.c("true") }, .{ "h_a_s__t_l_sv1_3", h.c("true") },
    .{ "s_s_l_error", h.err("SSLError") }, .{ "s_s_l_zero_return_error", h.err("SSLZeroReturnError") },
    .{ "s_s_l_want_read_error", h.err("SSLWantReadError") }, .{ "s_s_l_want_write_error", h.err("SSLWantWriteError") },
    .{ "s_s_l_syscall_error", h.err("SSLSyscallError") }, .{ "s_s_l_e_o_f_error", h.err("SSLEOFError") },
    .{ "s_s_l_cert_verification_error", h.err("SSLCertVerificationError") },
});
