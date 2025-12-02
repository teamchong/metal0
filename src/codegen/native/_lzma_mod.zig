/// Python _lzma module - Internal LZMA support (C accelerator)
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "l_z_m_a_compressor", h.c(".{ .format = 1, .check = 0 }") }, .{ "l_z_m_a_decompressor", h.c(".{ .format = 0, .eof = false, .needs_input = true, .unused_data = \"\" }") },
    .{ "compress", h.c("\"\"") }, .{ "flush", h.c("\"\"") }, .{ "decompress", h.c("\"\"") },
    .{ "is_check_supported", h.c("true") }, .{ "encode_filter_properties", h.c("\"\"") }, .{ "decode_filter_properties", h.c(".{}") },
    .{ "f_o_r_m_a_t__a_u_t_o", h.I32(0) }, .{ "f_o_r_m_a_t__x_z", h.I32(1) }, .{ "f_o_r_m_a_t__a_l_o_n_e", h.I32(2) }, .{ "f_o_r_m_a_t__r_a_w", h.I32(3) },
    .{ "c_h_e_c_k__n_o_n_e", h.I32(0) }, .{ "c_h_e_c_k__c_r_c32", h.I32(1) }, .{ "c_h_e_c_k__c_r_c64", h.I32(4) }, .{ "c_h_e_c_k__s_h_a256", h.I32(10) },
    .{ "p_r_e_s_e_t__d_e_f_a_u_l_t", h.I32(6) }, .{ "p_r_e_s_e_t__e_x_t_r_e_m_e", h.U32(0x80000000) },
    .{ "f_i_l_t_e_r__l_z_m_a1", h.I64(0x4000000000000001) }, .{ "f_i_l_t_e_r__l_z_m_a2", h.I64(0x21) },
    .{ "f_i_l_t_e_r__d_e_l_t_a", h.I64(0x03) }, .{ "f_i_l_t_e_r__x86", h.I64(0x04) },
    .{ "l_z_m_a_error", h.err("LZMAError") },
});
