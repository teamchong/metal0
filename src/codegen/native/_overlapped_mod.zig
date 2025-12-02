/// Python _overlapped module - Windows overlapped I/O
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "overlapped", h.c(".{}") }, .{ "create_event", h.c("0") }, .{ "create_io_completion_port", h.c("0") },
    .{ "get_queued_completion_status", h.c(".{ .bytes = 0, .key = 0, .overlapped = null }") },
    .{ "post_queued_completion_status", h.c("{}") }, .{ "reset_event", h.c("{}") }, .{ "set_event", h.c("{}") },
    .{ "format_message", h.c("\"\"") }, .{ "bind_local", h.c("{}") }, .{ "register_wait_with_queue", h.c("0") },
    .{ "unregister_wait", h.c("{}") }, .{ "unregister_wait_ex", h.c("{}") },
    .{ "connect_pipe", h.c(".{}") }, .{ "w_s_a_connect", h.c(".{}") },
    .{ "i_n_v_a_l_i_d__h_a_n_d_l_e__v_a_l_u_e", h.c("-1") }, .{ "n_u_l_l", h.c("0") },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", h.c("997") }, .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", h.c("64") },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", h.c("121") }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", h.c("231") },
    .{ "i_n_f_i_n_i_t_e", h.c("0xFFFFFFFF") },
});
