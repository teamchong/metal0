/// Python _msi module - Windows MSI database access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open_database", genEmpty }, .{ "create_record", genEmpty },
    .{ "uuid_create", genUuidCreate }, .{ "f_c_i_create", genUnit },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genI0 }, .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genI1 },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genI3 }, .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genI4 },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genI2 },
    .{ "p_i_d__c_o_d_e_p_a_g_e", genI1 }, .{ "p_i_d__t_i_t_l_e", genI2 }, .{ "p_i_d__s_u_b_j_e_c_t", genI3 },
    .{ "p_i_d__a_u_t_h_o_r", genI4 }, .{ "p_i_d__k_e_y_w_o_r_d_s", genI5 }, .{ "p_i_d__c_o_m_m_e_n_t_s", genI6 },
    .{ "p_i_d__t_e_m_p_l_a_t_e", genI7 }, .{ "p_i_d__r_e_v_n_u_m_b_e_r", genI9 },
    .{ "p_i_d__p_a_g_e_c_o_u_n_t", genI14 }, .{ "p_i_d__w_o_r_d_c_o_u_n_t", genI15 },
    .{ "p_i_d__a_p_p_n_a_m_e", genI18 }, .{ "p_i_d__s_e_c_u_r_i_t_y", genI19 },
});

fn genUuidCreate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"00000000-0000-0000-0000-000000000000\""); }
fn genI0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genI1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
fn genI2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn genI3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
fn genI4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
fn genI5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "5"); }
fn genI6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "6"); }
fn genI7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "7"); }
fn genI9(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "9"); }
fn genI14(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "14"); }
fn genI15(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "15"); }
fn genI18(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "18"); }
fn genI19(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "19"); }
