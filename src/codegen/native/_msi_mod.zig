/// Python _msi module - Windows MSI database access
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open_database", h.c(".{}") }, .{ "create_record", h.c(".{}") },
    .{ "uuid_create", h.c("\"00000000-0000-0000-0000-000000000000\"") }, .{ "f_c_i_create", h.c("{}") },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", h.c("0") }, .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", h.c("1") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", h.c("3") }, .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", h.c("4") },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", h.c("2") },
    .{ "p_i_d__c_o_d_e_p_a_g_e", h.c("1") }, .{ "p_i_d__t_i_t_l_e", h.c("2") }, .{ "p_i_d__s_u_b_j_e_c_t", h.c("3") },
    .{ "p_i_d__a_u_t_h_o_r", h.c("4") }, .{ "p_i_d__k_e_y_w_o_r_d_s", h.c("5") }, .{ "p_i_d__c_o_m_m_e_n_t_s", h.c("6") },
    .{ "p_i_d__t_e_m_p_l_a_t_e", h.c("7") }, .{ "p_i_d__r_e_v_n_u_m_b_e_r", h.c("9") },
    .{ "p_i_d__p_a_g_e_c_o_u_n_t", h.c("14") }, .{ "p_i_d__w_o_r_d_c_o_u_n_t", h.c("15") },
    .{ "p_i_d__a_p_p_n_a_m_e", h.c("18") }, .{ "p_i_d__s_e_c_u_r_i_t_y", h.c("19") },
});
