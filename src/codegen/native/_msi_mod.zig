/// Python _msi module - Windows MSI database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open_database", genConst(".{}") }, .{ "create_record", genConst(".{}") },
    .{ "uuid_create", genConst("\"00000000-0000-0000-0000-000000000000\"") }, .{ "f_c_i_create", genConst("{}") },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genConst("0") }, .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genConst("1") },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genConst("3") }, .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genConst("4") },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genConst("2") },
    .{ "p_i_d__c_o_d_e_p_a_g_e", genConst("1") }, .{ "p_i_d__t_i_t_l_e", genConst("2") }, .{ "p_i_d__s_u_b_j_e_c_t", genConst("3") },
    .{ "p_i_d__a_u_t_h_o_r", genConst("4") }, .{ "p_i_d__k_e_y_w_o_r_d_s", genConst("5") }, .{ "p_i_d__c_o_m_m_e_n_t_s", genConst("6") },
    .{ "p_i_d__t_e_m_p_l_a_t_e", genConst("7") }, .{ "p_i_d__r_e_v_n_u_m_b_e_r", genConst("9") },
    .{ "p_i_d__p_a_g_e_c_o_u_n_t", genConst("14") }, .{ "p_i_d__w_o_r_d_c_o_u_n_t", genConst("15") },
    .{ "p_i_d__a_p_p_n_a_m_e", genConst("18") }, .{ "p_i_d__s_e_c_u_r_i_t_y", genConst("19") },
});
