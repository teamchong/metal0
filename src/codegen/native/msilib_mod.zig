/// Python msilib module - Windows MSI file creation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "init_database", h.c(".{}") }, .{ "add_data", h.c("{}") }, .{ "add_tables", h.c("{}") },
    .{ "add_stream", h.c("{}") }, .{ "gen_uuid", h.c("\"{00000000-0000-0000-0000-000000000000}\"") },
    .{ "open_database", h.c(".{}") }, .{ "create_record", h.c(".{}") },
    .{ "c_a_b", h.c(".{}") }, .{ "directory", h.c(".{}") }, .{ "feature", h.c(".{}") },
    .{ "dialog", h.c(".{}") }, .{ "control", h.c(".{}") }, .{ "radio_button_group", h.c(".{}") },
    .{ "a_m_d64", h.c("false") }, .{ "win64", h.c("false") }, .{ "itanium", h.c("false") },
    .{ "schema", h.c(".{}") }, .{ "sequence", h.c(".{}") }, .{ "text", h.c(".{}") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", h.c("4") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", h.c("3") },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", h.c("2") },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", h.c("0") },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", h.c("1") },
});
