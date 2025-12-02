/// Python ossaudiodev module - OSS audio device access
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genEmpty }, .{ "openmixer", genEmpty }, .{ "error", genError },
    .{ "a_f_m_t__u8", gen0x08 }, .{ "a_f_m_t__s16__l_e", gen0x10 }, .{ "a_f_m_t__s16__b_e", gen0x20 },
    .{ "a_f_m_t__s16__n_e", gen0x10 }, .{ "a_f_m_t__a_c3", gen0x400 }, .{ "a_f_m_t__q_u_e_r_y", gen0 },
    .{ "s_n_d_c_t_l__d_s_p__c_h_a_n_n_e_l_s", genC0045006 }, .{ "s_n_d_c_t_l__d_s_p__g_e_t_f_m_t_s", gen8004500B },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_m_t", genC0045005 }, .{ "s_n_d_c_t_l__d_s_p__s_p_e_e_d", genC0045002 },
    .{ "s_n_d_c_t_l__d_s_p__s_t_e_r_e_o", genC0045003 }, .{ "s_n_d_c_t_l__d_s_p__s_y_n_c", gen5001 },
    .{ "s_n_d_c_t_l__d_s_p__r_e_s_e_t", gen5000 }, .{ "s_n_d_c_t_l__d_s_p__g_e_t_o_s_p_a_c_e", gen8010500C },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_i_s_p_a_c_e", gen8010500D }, .{ "s_n_d_c_t_l__d_s_p__n_o_n_b_l_o_c_k", gen500E },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_c_a_p_s", gen8004500F }, .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_r_a_g_m_e_n_t", genC004500A },
    .{ "s_o_u_n_d__m_i_x_e_r__n_r_d_e_v_i_c_e_s", gen25 }, .{ "s_o_u_n_d__m_i_x_e_r__v_o_l_u_m_e", gen0 },
    .{ "s_o_u_n_d__m_i_x_e_r__b_a_s_s", gen1 }, .{ "s_o_u_n_d__m_i_x_e_r__t_r_e_b_l_e", gen2 },
    .{ "s_o_u_n_d__m_i_x_e_r__p_c_m", gen4 }, .{ "s_o_u_n_d__m_i_x_e_r__l_i_n_e", gen6 },
    .{ "s_o_u_n_d__m_i_x_e_r__m_i_c", gen7 }, .{ "s_o_u_n_d__m_i_x_e_r__c_d", gen8 },
    .{ "s_o_u_n_d__m_i_x_e_r__r_e_c", gen11 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.OSSAudioError"); }
fn gen0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn gen1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
fn gen2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn gen4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
fn gen6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "6"); }
fn gen7(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "7"); }
fn gen8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "8"); }
fn gen11(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "11"); }
fn gen25(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "25"); }
fn gen0x08(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x08"); }
fn gen0x10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x10"); }
fn gen0x20(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20"); }
fn gen0x400(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x400"); }
fn gen5000(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x5000"); }
fn gen5001(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x5001"); }
fn gen500E(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x500E"); }
fn genC0045002(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xC0045002"); }
fn genC0045003(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xC0045003"); }
fn genC0045005(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xC0045005"); }
fn genC0045006(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xC0045006"); }
fn genC004500A(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0xC004500A"); }
fn gen8004500B(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8004500B"); }
fn gen8004500F(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8004500F"); }
fn gen8010500C(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8010500C"); }
fn gen8010500D(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8010500D"); }
