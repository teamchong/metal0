/// Python _ast module - Internal AST support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "py_c_f__o_n_l_y__a_s_t", h.c("@as(i32, 0x0400)") },
    .{ "py_c_f__t_y_p_e__c_o_m_m_e_n_t_s", h.c("@as(i32, 0x1000)") },
    .{ "py_c_f__a_l_l_o_w__t_o_p__l_e_v_e_l__a_w_a_i_t", h.c("@as(i32, 0x2000)") },
});
