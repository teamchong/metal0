/// Python msvcrt module - Windows MSVC runtime routines
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getch", h.c("\"\"") }, .{ "getwch", h.c("\"\"") }, .{ "getche", h.c("\"\"") }, .{ "getwche", h.c("\"\"") },
    .{ "putch", h.c("{}") }, .{ "putwch", h.c("{}") }, .{ "ungetch", h.c("{}") }, .{ "ungetwch", h.c("{}") },
    .{ "kbhit", h.c("false") }, .{ "locking", h.c("{}") }, .{ "setmode", h.c("0") }, .{ "heapmin", h.c("{}") },
    .{ "open_osfhandle", h.c("-1") }, .{ "get_osfhandle", h.c("-1") }, .{ "set_error_mode", h.c("0") },
    .{ "c_r_t__a_s_s_e_m_b_l_y__v_e_r_s_i_o_n", h.c("\"\"") },
    .{ "l_k__n_b_l_c_k", h.c("2") }, .{ "l_k__n_b_r_l_c_k", h.c("4") },
    .{ "l_k__l_o_c_k", h.c("1") }, .{ "l_k__r_l_c_k", h.c("3") }, .{ "l_k__u_n_l_c_k", h.c("0") },
    .{ "s_e_m__f_a_i_l_c_r_i_t_i_c_a_l_e_r_r_o_r_s", h.c("1") },
    .{ "s_e_m__n_o_a_l_i_g_n_m_e_n_t_f_a_u_l_t_e_x_c_e_p_t", h.c("4") },
    .{ "s_e_m__n_o_g_p_f_a_u_l_t_e_r_r_o_r_b_o_x", h.c("2") },
    .{ "s_e_m__n_o_o_p_e_n_f_i_l_e_e_r_r_o_r_b_o_x", h.c("0x8000") },
});
