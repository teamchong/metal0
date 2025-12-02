/// Python _symtable module - Internal symtable support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "symtable", h.c(".{ .name = \"top\", .type = \"module\", .id = 0, .lineno = 0 }") },
    .{ "s_c_o_p_e__o_f_f", h.I32(11) }, .{ "s_c_o_p_e__m_a_s_k", h.c("@as(i32, 0xf)") },
    .{ "l_o_c_a_l", h.I32(1) }, .{ "g_l_o_b_a_l__e_x_p_l_i_c_i_t", h.I32(2) }, .{ "g_l_o_b_a_l__i_m_p_l_i_c_i_t", h.I32(3) },
    .{ "f_r_e_e", h.I32(4) }, .{ "c_e_l_l", h.I32(5) },
    .{ "t_y_p_e__f_u_n_c_t_i_o_n", h.I32(1) }, .{ "t_y_p_e__c_l_a_s_s", h.I32(2) }, .{ "t_y_p_e__m_o_d_u_l_e", h.I32(0) },
});
