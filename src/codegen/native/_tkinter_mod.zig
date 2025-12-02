/// Python _tkinter module - Tcl/Tk interface
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "create", h.c(".{}") }, .{ "setbusywaitinterval", h.c("{}") }, .{ "getbusywaitinterval", h.c("20") },
    .{ "tcl_error", h.err("TclError") }, .{ "t_k__v_e_r_s_i_o_n", h.c("\"8.6\"") }, .{ "t_c_l__v_e_r_s_i_o_n", h.c("\"8.6\"") },
    .{ "r_e_a_d_a_b_l_e", h.c("2") }, .{ "w_r_i_t_a_b_l_e", h.c("4") }, .{ "e_x_c_e_p_t_i_o_n", h.c("8") },
    .{ "d_o_n_t__w_a_i_t", h.c("2") }, .{ "w_i_n_d_o_w__e_v_e_n_t_s", h.c("4") }, .{ "f_i_l_e__e_v_e_n_t_s", h.c("8") },
    .{ "t_i_m_e_r__e_v_e_n_t_s", h.c("16") }, .{ "i_d_l_e__e_v_e_n_t_s", h.c("32") }, .{ "a_l_l__e_v_e_n_t_s", h.c("-3") },
});
