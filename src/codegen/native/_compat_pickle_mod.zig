/// Python _compat_pickle module - Pickle compatibility mappings for Python 2/3
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "n_a_m_e__m_a_p_p_i_n_g", h.c(".{}") },
    .{ "i_m_p_o_r_t__m_a_p_p_i_n_g", h.c(".{}") },
    .{ "r_e_v_e_r_s_e__n_a_m_e__m_a_p_p_i_n_g", h.c(".{}") },
    .{ "r_e_v_e_r_s_e__i_m_p_o_r_t__m_a_p_p_i_n_g", h.c(".{}") },
});
