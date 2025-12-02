/// Python winreg module - Windows registry access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genEnumVal(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", null, 0 }"); }
fn genQueryInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ 0, 0, 0 }"); }
fn genQueryValEx(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ null, 0 }"); }
fn genHex(comptime v: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, v); } }.f;
}
fn genInt(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("{}", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "close_key", genUnit }, .{ "connect_registry", genNull }, .{ "create_key", genNull }, .{ "create_key_ex", genNull },
    .{ "delete_key", genUnit }, .{ "delete_key_ex", genUnit }, .{ "delete_value", genUnit },
    .{ "enum_key", genEmptyStr }, .{ "enum_value", genEnumVal }, .{ "expand_environment_strings", genEmptyStr },
    .{ "flush_key", genUnit }, .{ "load_key", genUnit }, .{ "open_key", genNull }, .{ "open_key_ex", genNull },
    .{ "query_info_key", genQueryInfo }, .{ "query_value", genEmptyStr }, .{ "query_value_ex", genQueryValEx },
    .{ "save_key", genUnit }, .{ "set_value", genUnit }, .{ "set_value_ex", genUnit },
    .{ "disable_reflection_key", genUnit }, .{ "enable_reflection_key", genUnit }, .{ "query_reflection_key", genFalse },
    .{ "h_k_e_y__c_l_a_s_s_e_s__r_o_o_t", genHex("0x80000000") }, .{ "h_k_e_y__c_u_r_r_e_n_t__u_s_e_r", genHex("0x80000001") },
    .{ "h_k_e_y__l_o_c_a_l__m_a_c_h_i_n_e", genHex("0x80000002") }, .{ "h_k_e_y__u_s_e_r_s", genHex("0x80000003") },
    .{ "h_k_e_y__p_e_r_f_o_r_m_a_n_c_e__d_a_t_a", genHex("0x80000004") }, .{ "h_k_e_y__c_u_r_r_e_n_t__c_o_n_f_i_g", genHex("0x80000005") }, .{ "h_k_e_y__d_y_n__d_a_t_a", genHex("0x80000006") },
    .{ "k_e_y__a_l_l__a_c_c_e_s_s", genHex("0xF003F") }, .{ "k_e_y__w_r_i_t_e", genHex("0x20006") }, .{ "k_e_y__r_e_a_d", genHex("0x20019") }, .{ "k_e_y__e_x_e_c_u_t_e", genHex("0x20019") },
    .{ "k_e_y__q_u_e_r_y__v_a_l_u_e", genHex("0x0001") }, .{ "k_e_y__s_e_t__v_a_l_u_e", genHex("0x0002") }, .{ "k_e_y__c_r_e_a_t_e__s_u_b__k_e_y", genHex("0x0004") },
    .{ "k_e_y__e_n_u_m_e_r_a_t_e__s_u_b__k_e_y_s", genHex("0x0008") }, .{ "k_e_y__n_o_t_i_f_y", genHex("0x0010") }, .{ "k_e_y__c_r_e_a_t_e__l_i_n_k", genHex("0x0020") },
    .{ "k_e_y__w_o_w64_64_k_e_y", genHex("0x0100") }, .{ "k_e_y__w_o_w64_32_k_e_y", genHex("0x0200") },
    .{ "r_e_g__n_o_n_e", genInt(0) }, .{ "r_e_g__s_z", genInt(1) }, .{ "r_e_g__e_x_p_a_n_d__s_z", genInt(2) }, .{ "r_e_g__b_i_n_a_r_y", genInt(3) },
    .{ "r_e_g__d_w_o_r_d", genInt(4) }, .{ "r_e_g__d_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genInt(4) }, .{ "r_e_g__d_w_o_r_d__b_i_g__e_n_d_i_a_n", genInt(5) },
    .{ "r_e_g__l_i_n_k", genInt(6) }, .{ "r_e_g__m_u_l_t_i__s_z", genInt(7) }, .{ "r_e_g__r_e_s_o_u_r_c_e__l_i_s_t", genInt(8) },
    .{ "r_e_g__f_u_l_l__r_e_s_o_u_r_c_e__d_e_s_c_r_i_p_t_o_r", genInt(9) }, .{ "r_e_g__r_e_s_o_u_r_c_e__r_e_q_u_i_r_e_m_e_n_t_s__l_i_s_t", genInt(10) },
    .{ "r_e_g__q_w_o_r_d", genInt(11) }, .{ "r_e_g__q_w_o_r_d__l_i_t_t_l_e__e_n_d_i_a_n", genInt(11) },
});
