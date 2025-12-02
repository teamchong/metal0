/// Python ossaudiodev module - OSS audio device access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genConst(".{}") }, .{ "openmixer", genConst(".{}") }, .{ "error", genConst("error.OSSAudioError") },
    .{ "a_f_m_t__u8", genConst("0x08") }, .{ "a_f_m_t__s16__l_e", genConst("0x10") },
    .{ "a_f_m_t__s16__b_e", genConst("0x20") }, .{ "a_f_m_t__s16__n_e", genConst("0x10") },
    .{ "a_f_m_t__a_c3", genConst("0x400") }, .{ "a_f_m_t__q_u_e_r_y", genConst("0") },
    .{ "s_n_d_c_t_l__d_s_p__c_h_a_n_n_e_l_s", genConst("0xC0045006") },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_f_m_t_s", genConst("0x8004500B") },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_m_t", genConst("0xC0045005") },
    .{ "s_n_d_c_t_l__d_s_p__s_p_e_e_d", genConst("0xC0045002") },
    .{ "s_n_d_c_t_l__d_s_p__s_t_e_r_e_o", genConst("0xC0045003") },
    .{ "s_n_d_c_t_l__d_s_p__s_y_n_c", genConst("0x5001") },
    .{ "s_n_d_c_t_l__d_s_p__r_e_s_e_t", genConst("0x5000") },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_o_s_p_a_c_e", genConst("0x8010500C") },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_i_s_p_a_c_e", genConst("0x8010500D") },
    .{ "s_n_d_c_t_l__d_s_p__n_o_n_b_l_o_c_k", genConst("0x500E") },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_c_a_p_s", genConst("0x8004500F") },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_r_a_g_m_e_n_t", genConst("0xC004500A") },
    .{ "s_o_u_n_d__m_i_x_e_r__n_r_d_e_v_i_c_e_s", genConst("25") },
    .{ "s_o_u_n_d__m_i_x_e_r__v_o_l_u_m_e", genConst("0") },
    .{ "s_o_u_n_d__m_i_x_e_r__b_a_s_s", genConst("1") }, .{ "s_o_u_n_d__m_i_x_e_r__t_r_e_b_l_e", genConst("2") },
    .{ "s_o_u_n_d__m_i_x_e_r__p_c_m", genConst("4") }, .{ "s_o_u_n_d__m_i_x_e_r__l_i_n_e", genConst("6") },
    .{ "s_o_u_n_d__m_i_x_e_r__m_i_c", genConst("7") }, .{ "s_o_u_n_d__m_i_x_e_r__c_d", genConst("8") },
    .{ "s_o_u_n_d__m_i_x_e_r__r_e_c", genConst("11") },
});
