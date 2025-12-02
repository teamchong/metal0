/// Python _winapi module - Windows API functions
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Functions
    .{ "close_handle", h.c("{}") }, .{ "create_file", h.c("0") }, .{ "create_junction", h.c("{}") },
    .{ "create_named_pipe", h.c("0") }, .{ "create_pipe", h.c(".{ .read = 0, .write = 0 }") },
    .{ "create_process", h.c(".{ .process = 0, .thread = 0, .pid = 0, .tid = 0 }") },
    .{ "duplicate_handle", h.c("0") }, .{ "exit_process", h.c("{}") }, .{ "get_current_process", h.c("-1") },
    .{ "get_exit_code_process", h.c("0") }, .{ "get_last_error", h.c("0") }, .{ "get_module_file_name", h.c("\"\"") },
    .{ "get_std_handle", h.c("0") }, .{ "get_version", h.c("0") }, .{ "open_process", h.c("0") },
    .{ "peek_named_pipe", h.c(".{ .data = \"\", .available = 0, .message = 0 }") },
    .{ "read_file", h.c(".{ .data = \"\", .error = 0 }") }, .{ "set_named_pipe_handle_state", h.c("{}") },
    .{ "terminate_process", h.c("{}") }, .{ "wait_for_multiple_objects", h.c("0") }, .{ "wait_for_single_object", h.c("0") },
    .{ "wait_named_pipe", h.c("{}") }, .{ "write_file", h.c(".{ .written = 0, .error = 0 }") },
    .{ "connect_named_pipe", h.c("{}") }, .{ "get_file_type", h.c("1") },
    // Constants
    .{ "s_t_d__i_n_p_u_t__h_a_n_d_l_e", h.c("-10") }, .{ "s_t_d__o_u_t_p_u_t__h_a_n_d_l_e", h.c("-11") },
    .{ "s_t_d__e_r_r_o_r__h_a_n_d_l_e", h.c("-12") }, .{ "d_u_p_l_i_c_a_t_e__s_a_m_e__a_c_c_e_s_s", h.c("2") },
    .{ "d_u_p_l_i_c_a_t_e__c_l_o_s_e__s_o_u_r_c_e", h.c("1") }, .{ "s_t_a_r_t_u_p_i_n_f_o", h.c(".{}") },
    .{ "i_n_f_i_n_i_t_e", h.c("0xFFFFFFFF") }, .{ "w_a_i_t__o_b_j_e_c_t_0", h.c("0") },
    .{ "w_a_i_t__a_b_a_n_d_o_n_e_d_0", h.c("0x80") }, .{ "w_a_i_t__t_i_m_e_o_u_t", h.c("258") },
    .{ "c_r_e_a_t_e__n_e_w__c_o_n_s_o_l_e", h.c("0x10") }, .{ "c_r_e_a_t_e__n_e_w__p_r_o_c_e_s_s__g_r_o_u_p", h.c("0x200") },
    .{ "s_t_i_l_l__a_c_t_i_v_e", h.c("259") }, .{ "p_i_p_e__a_c_c_e_s_s__i_n_b_o_u_n_d", h.c("1") },
    .{ "p_i_p_e__a_c_c_e_s_s__o_u_t_b_o_u_n_d", h.c("2") }, .{ "p_i_p_e__a_c_c_e_s_s__d_u_p_l_e_x", h.c("3") },
    .{ "n_m_p_w_a_i_t__w_a_i_t__f_o_r_e_v_e_r", h.c("0xFFFFFFFF") }, .{ "g_e_n_e_r_i_c__r_e_a_d", h.c("0x80000000") },
    .{ "g_e_n_e_r_i_c__w_r_i_t_e", h.c("0x40000000") }, .{ "o_p_e_n__e_x_i_s_t_i_n_g", h.c("3") },
    .{ "f_i_l_e__f_l_a_g__o_v_e_r_l_a_p_p_e_d", h.c("0x40000000") }, .{ "f_i_l_e__f_l_a_g__f_i_r_s_t__p_i_p_e__i_n_s_t_a_n_c_e", h.c("0x80000") },
    .{ "p_i_p_e__w_a_i_t", h.c("0") }, .{ "p_i_p_e__t_y_p_e__m_e_s_s_a_g_e", h.c("4") },
    .{ "p_i_p_e__r_e_a_d_m_o_d_e__m_e_s_s_a_g_e", h.c("2") }, .{ "p_i_p_e__u_n_l_i_m_i_t_e_d__i_n_s_t_a_n_c_e_s", h.c("255") },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", h.c("997") }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", h.c("231") },
    .{ "e_r_r_o_r__a_l_r_e_a_d_y__e_x_i_s_t_s", h.c("183") }, .{ "e_r_r_o_r__b_r_o_k_e_n__p_i_p_e", h.c("109") },
    .{ "e_r_r_o_r__n_o__d_a_t_a", h.c("232") }, .{ "e_r_r_o_r__n_o__s_y_s_t_e_m__r_e_s_o_u_r_c_e_s", h.c("1450") },
    .{ "e_r_r_o_r__o_p_e_r_a_t_i_o_n__a_b_o_r_t_e_d", h.c("995") }, .{ "e_r_r_o_r__p_i_p_e__c_o_n_n_e_c_t_e_d", h.c("535") },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", h.c("121") }, .{ "e_r_r_o_r__m_o_r_e__d_a_t_a", h.c("234") },
    .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", h.c("64") }, .{ "n_u_l_l", h.c("0") },
});
