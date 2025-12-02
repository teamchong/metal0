/// Python winsound module - Windows sound playing interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "beep", genConst("{}") }, .{ "play_sound", genConst("{}") }, .{ "message_beep", genConst("{}") },
    .{ "s_n_d__f_i_l_e_n_a_m_e", genConst("0x20000") }, .{ "s_n_d__a_l_i_a_s", genConst("0x10000") },
    .{ "s_n_d__l_o_o_p", genConst("0x0008") }, .{ "s_n_d__m_e_m_o_r_y", genConst("0x0004") },
    .{ "s_n_d__p_u_r_g_e", genConst("0x0040") }, .{ "s_n_d__a_s_y_n_c", genConst("0x0001") },
    .{ "s_n_d__n_o_d_e_f_a_u_l_t", genConst("0x0002") }, .{ "s_n_d__n_o_s_t_o_p", genConst("0x0010") },
    .{ "s_n_d__n_o_w_a_i_t", genConst("0x2000") },
    .{ "m_b__i_c_o_n_a_s_t_e_r_i_s_k", genConst("0x40") }, .{ "m_b__i_c_o_n_e_x_c_l_a_m_a_t_i_o_n", genConst("0x30") },
    .{ "m_b__i_c_o_n_h_a_n_d", genConst("0x10") }, .{ "m_b__i_c_o_n_q_u_e_s_t_i_o_n", genConst("0x20") },
    .{ "m_b__o_k", genConst("0x0") },
});
