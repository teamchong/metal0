/// Python winsound module - Windows sound playing interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "beep", h.c("{}") }, .{ "play_sound", h.c("{}") }, .{ "message_beep", h.c("{}") },
    .{ "s_n_d__f_i_l_e_n_a_m_e", h.c("0x20000") }, .{ "s_n_d__a_l_i_a_s", h.c("0x10000") },
    .{ "s_n_d__l_o_o_p", h.c("0x0008") }, .{ "s_n_d__m_e_m_o_r_y", h.c("0x0004") },
    .{ "s_n_d__p_u_r_g_e", h.c("0x0040") }, .{ "s_n_d__a_s_y_n_c", h.c("0x0001") },
    .{ "s_n_d__n_o_d_e_f_a_u_l_t", h.c("0x0002") }, .{ "s_n_d__n_o_s_t_o_p", h.c("0x0010") },
    .{ "s_n_d__n_o_w_a_i_t", h.c("0x2000") },
    .{ "m_b__i_c_o_n_a_s_t_e_r_i_s_k", h.c("0x40") }, .{ "m_b__i_c_o_n_e_x_c_l_a_m_a_t_i_o_n", h.c("0x30") },
    .{ "m_b__i_c_o_n_h_a_n_d", h.c("0x10") }, .{ "m_b__i_c_o_n_q_u_e_s_t_i_o_n", h.c("0x20") },
    .{ "m_b__o_k", h.c("0x0") },
});
