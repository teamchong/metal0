/// Python tkinter module - Tk GUI toolkit
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Widgets (all emit .{})
    .{ "tk", h.c(".{}") }, .{ "frame", h.c(".{}") }, .{ "label", h.c(".{}") }, .{ "button", h.c(".{}") },
    .{ "entry", h.c(".{}") }, .{ "text", h.c(".{}") }, .{ "canvas", h.c(".{}") }, .{ "listbox", h.c(".{}") },
    .{ "menu", h.c(".{}") }, .{ "menubutton", h.c(".{}") }, .{ "scrollbar", h.c(".{}") }, .{ "scale", h.c(".{}") },
    .{ "spinbox", h.c(".{}") }, .{ "checkbutton", h.c(".{}") }, .{ "radiobutton", h.c(".{}") },
    .{ "message", h.c(".{}") }, .{ "toplevel", h.c(".{}") }, .{ "paned_window", h.c(".{}") },
    .{ "label_frame", h.c(".{}") }, .{ "photo_image", h.c(".{}") }, .{ "bitmap_image", h.c(".{}") },
    // Variables
    .{ "string_var", h.c(".{ .value = \"\" }") }, .{ "int_var", h.c(".{ .value = 0 }") },
    .{ "double_var", h.c(".{ .value = 0.0 }") }, .{ "boolean_var", h.c(".{ .value = false }") },
    // Functions
    .{ "mainloop", h.c("{}") }, .{ "tcl_error", h.err("TclError") },
    // Constants
    .{ "e_n_d", h.c("\"end\"") }, .{ "l_e_f_t", h.c("\"left\"") }, .{ "r_i_g_h_t", h.c("\"right\"") }, .{ "t_o_p", h.c("\"top\"") },
    .{ "b_o_t_t_o_m", h.c("\"bottom\"") }, .{ "c_e_n_t_e_r", h.c("\"center\"") },
    .{ "n", h.c("\"n\"") }, .{ "s", h.c("\"s\"") }, .{ "e", h.c("\"e\"") }, .{ "w", h.c("\"w\"") },
    .{ "n_e", h.c("\"ne\"") }, .{ "n_w", h.c("\"nw\"") }, .{ "s_e", h.c("\"se\"") }, .{ "s_w", h.c("\"sw\"") },
    .{ "h_o_r_i_z_o_n_t_a_l", h.c("\"horizontal\"") }, .{ "v_e_r_t_i_c_a_l", h.c("\"vertical\"") }, .{ "b_o_t_h", h.c("\"both\"") },
    .{ "x", h.c("\"x\"") }, .{ "y", h.c("\"y\"") }, .{ "n_o_n_e", h.c("\"none\"") },
    .{ "r_a_i_s_e_d", h.c("\"raised\"") }, .{ "s_u_n_k_e_n", h.c("\"sunken\"") }, .{ "f_l_a_t", h.c("\"flat\"") },
    .{ "r_i_d_g_e", h.c("\"ridge\"") }, .{ "g_r_o_o_v_e", h.c("\"groove\"") }, .{ "s_o_l_i_d", h.c("\"solid\"") },
    .{ "n_o_r_m_a_l", h.c("\"normal\"") }, .{ "d_i_s_a_b_l_e_d", h.c("\"disabled\"") }, .{ "a_c_t_i_v_e", h.c("\"active\"") }, .{ "h_i_d_d_e_n", h.c("\"hidden\"") },
    .{ "i_n_s_e_r_t", h.c("\"insert\"") }, .{ "s_e_l", h.c("\"sel\"") }, .{ "s_e_l__f_i_r_s_t", h.c("\"sel.first\"") }, .{ "s_e_l__l_a_s_t", h.c("\"sel.last\"") },
    .{ "w_o_r_d", h.c("\"word\"") }, .{ "c_h_a_r", h.c("\"char\"") },
});
