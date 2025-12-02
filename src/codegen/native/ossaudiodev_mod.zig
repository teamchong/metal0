/// Python ossaudiodev module - OSS audio device access
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", h.c(".{}") }, .{ "openmixer", h.c(".{}") }, .{ "error", h.err("OSSAudioError") },
    .{ "a_f_m_t__u8", h.hex32(0x08) }, .{ "a_f_m_t__s16__l_e", h.hex32(0x10) },
    .{ "a_f_m_t__s16__b_e", h.hex32(0x20) }, .{ "a_f_m_t__s16__n_e", h.hex32(0x10) },
    .{ "a_f_m_t__a_c3", h.hex32(0x400) }, .{ "a_f_m_t__q_u_e_r_y", h.I32(0) },
    .{ "s_n_d_c_t_l__d_s_p__c_h_a_n_n_e_l_s", h.hex32(0xC0045006) },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_f_m_t_s", h.hex32(0x8004500B) },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_m_t", h.hex32(0xC0045005) },
    .{ "s_n_d_c_t_l__d_s_p__s_p_e_e_d", h.hex32(0xC0045002) },
    .{ "s_n_d_c_t_l__d_s_p__s_t_e_r_e_o", h.hex32(0xC0045003) },
    .{ "s_n_d_c_t_l__d_s_p__s_y_n_c", h.hex32(0x5001) },
    .{ "s_n_d_c_t_l__d_s_p__r_e_s_e_t", h.hex32(0x5000) },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_o_s_p_a_c_e", h.hex32(0x8010500C) },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_i_s_p_a_c_e", h.hex32(0x8010500D) },
    .{ "s_n_d_c_t_l__d_s_p__n_o_n_b_l_o_c_k", h.hex32(0x500E) },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_c_a_p_s", h.hex32(0x8004500F) },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_r_a_g_m_e_n_t", h.hex32(0xC004500A) },
    .{ "s_o_u_n_d__m_i_x_e_r__n_r_d_e_v_i_c_e_s", h.I32(25) },
    .{ "s_o_u_n_d__m_i_x_e_r__v_o_l_u_m_e", h.I32(0) },
    .{ "s_o_u_n_d__m_i_x_e_r__b_a_s_s", h.I32(1) }, .{ "s_o_u_n_d__m_i_x_e_r__t_r_e_b_l_e", h.I32(2) },
    .{ "s_o_u_n_d__m_i_x_e_r__p_c_m", h.I32(4) }, .{ "s_o_u_n_d__m_i_x_e_r__l_i_n_e", h.I32(6) },
    .{ "s_o_u_n_d__m_i_x_e_r__m_i_c", h.I32(7) }, .{ "s_o_u_n_d__m_i_x_e_r__c_d", h.I32(8) },
    .{ "s_o_u_n_d__m_i_x_e_r__r_e_c", h.I32(11) },
});
