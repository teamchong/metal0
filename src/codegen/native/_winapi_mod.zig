/// Python _winapi module - Windows API functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn gen0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genInt(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("{}", .{n})); } }.f;
}
fn genHex(comptime v: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, v); } }.f;
}
fn genStruct(comptime v: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Functions
    .{ "close_handle", genUnit }, .{ "create_file", gen0 }, .{ "create_junction", genUnit },
    .{ "create_named_pipe", gen0 }, .{ "create_pipe", genStruct(".{ .read = 0, .write = 0 }") },
    .{ "create_process", genStruct(".{ .process = 0, .thread = 0, .pid = 0, .tid = 0 }") },
    .{ "duplicate_handle", gen0 }, .{ "exit_process", genUnit }, .{ "get_current_process", genInt(-1) },
    .{ "get_exit_code_process", gen0 }, .{ "get_last_error", gen0 }, .{ "get_module_file_name", genEmptyStr },
    .{ "get_std_handle", gen0 }, .{ "get_version", gen0 }, .{ "open_process", gen0 },
    .{ "peek_named_pipe", genStruct(".{ .data = \"\", .available = 0, .message = 0 }") },
    .{ "read_file", genStruct(".{ .data = \"\", .error = 0 }") }, .{ "set_named_pipe_handle_state", genUnit },
    .{ "terminate_process", genUnit }, .{ "wait_for_multiple_objects", gen0 }, .{ "wait_for_single_object", gen0 },
    .{ "wait_named_pipe", genUnit }, .{ "write_file", genStruct(".{ .written = 0, .error = 0 }") },
    .{ "connect_named_pipe", genUnit }, .{ "get_file_type", genInt(1) },
    // Constants
    .{ "s_t_d__i_n_p_u_t__h_a_n_d_l_e", genInt(-10) }, .{ "s_t_d__o_u_t_p_u_t__h_a_n_d_l_e", genInt(-11) },
    .{ "s_t_d__e_r_r_o_r__h_a_n_d_l_e", genInt(-12) }, .{ "d_u_p_l_i_c_a_t_e__s_a_m_e__a_c_c_e_s_s", genInt(2) },
    .{ "d_u_p_l_i_c_a_t_e__c_l_o_s_e__s_o_u_r_c_e", genInt(1) }, .{ "s_t_a_r_t_u_p_i_n_f_o", genEmpty },
    .{ "i_n_f_i_n_i_t_e", genHex("0xFFFFFFFF") }, .{ "w_a_i_t__o_b_j_e_c_t_0", gen0 },
    .{ "w_a_i_t__a_b_a_n_d_o_n_e_d_0", genHex("0x80") }, .{ "w_a_i_t__t_i_m_e_o_u_t", genInt(258) },
    .{ "c_r_e_a_t_e__n_e_w__c_o_n_s_o_l_e", genHex("0x10") }, .{ "c_r_e_a_t_e__n_e_w__p_r_o_c_e_s_s__g_r_o_u_p", genHex("0x200") },
    .{ "s_t_i_l_l__a_c_t_i_v_e", genInt(259) }, .{ "p_i_p_e__a_c_c_e_s_s__i_n_b_o_u_n_d", genInt(1) },
    .{ "p_i_p_e__a_c_c_e_s_s__o_u_t_b_o_u_n_d", genInt(2) }, .{ "p_i_p_e__a_c_c_e_s_s__d_u_p_l_e_x", genInt(3) },
    .{ "n_m_p_w_a_i_t__w_a_i_t__f_o_r_e_v_e_r", genHex("0xFFFFFFFF") }, .{ "g_e_n_e_r_i_c__r_e_a_d", genHex("0x80000000") },
    .{ "g_e_n_e_r_i_c__w_r_i_t_e", genHex("0x40000000") }, .{ "o_p_e_n__e_x_i_s_t_i_n_g", genInt(3) },
    .{ "f_i_l_e__f_l_a_g__o_v_e_r_l_a_p_p_e_d", genHex("0x40000000") }, .{ "f_i_l_e__f_l_a_g__f_i_r_s_t__p_i_p_e__i_n_s_t_a_n_c_e", genHex("0x80000") },
    .{ "p_i_p_e__w_a_i_t", gen0 }, .{ "p_i_p_e__t_y_p_e__m_e_s_s_a_g_e", genInt(4) },
    .{ "p_i_p_e__r_e_a_d_m_o_d_e__m_e_s_s_a_g_e", genInt(2) }, .{ "p_i_p_e__u_n_l_i_m_i_t_e_d__i_n_s_t_a_n_c_e_s", genInt(255) },
    .{ "e_r_r_o_r__i_o__p_e_n_d_i_n_g", genInt(997) }, .{ "e_r_r_o_r__p_i_p_e__b_u_s_y", genInt(231) },
    .{ "e_r_r_o_r__a_l_r_e_a_d_y__e_x_i_s_t_s", genInt(183) }, .{ "e_r_r_o_r__b_r_o_k_e_n__p_i_p_e", genInt(109) },
    .{ "e_r_r_o_r__n_o__d_a_t_a", genInt(232) }, .{ "e_r_r_o_r__n_o__s_y_s_t_e_m__r_e_s_o_u_r_c_e_s", genInt(1450) },
    .{ "e_r_r_o_r__o_p_e_r_a_t_i_o_n__a_b_o_r_t_e_d", genInt(995) }, .{ "e_r_r_o_r__p_i_p_e__c_o_n_n_e_c_t_e_d", genInt(535) },
    .{ "e_r_r_o_r__s_e_m__t_i_m_e_o_u_t", genInt(121) }, .{ "e_r_r_o_r__m_o_r_e__d_a_t_a", genInt(234) },
    .{ "e_r_r_o_r__n_e_t_n_a_m_e__d_e_l_e_t_e_d", genInt(64) }, .{ "n_u_l_l", gen0 },
});
