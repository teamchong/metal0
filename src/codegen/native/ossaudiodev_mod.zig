/// Python ossaudiodev module - OSS audio device access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genEmptyStruct },
    .{ "openmixer", genEmptyStruct },
    .{ "error", genError },
    .{ "a_f_m_t__u8", genAfmtU8 },
    .{ "a_f_m_t__s16__l_e", genAfmtS16Le },
    .{ "a_f_m_t__s16__b_e", genAfmtS16Be },
    .{ "a_f_m_t__s16__n_e", genAfmtS16Le },
    .{ "a_f_m_t__a_c3", genAfmtAc3 },
    .{ "a_f_m_t__q_u_e_r_y", genZero },
    .{ "s_n_d_c_t_l__d_s_p__c_h_a_n_n_e_l_s", genSndctlDspChannels },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_f_m_t_s", genSndctlDspGetfmts },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_m_t", genSndctlDspSetfmt },
    .{ "s_n_d_c_t_l__d_s_p__s_p_e_e_d", genSndctlDspSpeed },
    .{ "s_n_d_c_t_l__d_s_p__s_t_e_r_e_o", genSndctlDspStereo },
    .{ "s_n_d_c_t_l__d_s_p__s_y_n_c", genSndctlDspSync },
    .{ "s_n_d_c_t_l__d_s_p__r_e_s_e_t", genSndctlDspReset },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_o_s_p_a_c_e", genSndctlDspGetospace },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_i_s_p_a_c_e", genSndctlDspGetispace },
    .{ "s_n_d_c_t_l__d_s_p__n_o_n_b_l_o_c_k", genSndctlDspNonblock },
    .{ "s_n_d_c_t_l__d_s_p__g_e_t_c_a_p_s", genSndctlDspGetcaps },
    .{ "s_n_d_c_t_l__d_s_p__s_e_t_f_r_a_g_m_e_n_t", genSndctlDspSetfragment },
    .{ "s_o_u_n_d__m_i_x_e_r__n_r_d_e_v_i_c_e_s", gen25 },
    .{ "s_o_u_n_d__m_i_x_e_r__v_o_l_u_m_e", genZero },
    .{ "s_o_u_n_d__m_i_x_e_r__b_a_s_s", gen1 },
    .{ "s_o_u_n_d__m_i_x_e_r__t_r_e_b_l_e", gen2 },
    .{ "s_o_u_n_d__m_i_x_e_r__p_c_m", gen4 },
    .{ "s_o_u_n_d__m_i_x_e_r__l_i_n_e", gen6 },
    .{ "s_o_u_n_d__m_i_x_e_r__m_i_c", gen7 },
    .{ "s_o_u_n_d__m_i_x_e_r__c_d", gen8 },
    .{ "s_o_u_n_d__m_i_x_e_r__r_e_c", gen11 },
});

fn genEmptyStruct(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.OSSAudioError"), builder_mod.EmitConfig.forExpression());
}

fn genZero(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn gen1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn gen2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 2)"), builder_mod.EmitConfig.forExpression());
}

fn gen4(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 4)"), builder_mod.EmitConfig.forExpression());
}

fn gen6(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 6)"), builder_mod.EmitConfig.forExpression());
}

fn gen7(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 7)"), builder_mod.EmitConfig.forExpression());
}

fn gen8(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 8)"), builder_mod.EmitConfig.forExpression());
}

fn gen11(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 11)"), builder_mod.EmitConfig.forExpression());
}

fn gen25(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 25)"), builder_mod.EmitConfig.forExpression());
}

fn genAfmtU8(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x08)"), builder_mod.EmitConfig.forExpression());
}

fn genAfmtS16Le(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x10)"), builder_mod.EmitConfig.forExpression());
}

fn genAfmtS16Be(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x20)"), builder_mod.EmitConfig.forExpression());
}

fn genAfmtAc3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x400)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspChannels(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xC0045006)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspGetfmts(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x8004500B)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspSetfmt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xC0045005)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspSpeed(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xC0045002)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspStereo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xC0045003)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspSync(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x5001)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspReset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x5000)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspGetospace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x8010500C)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspGetispace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x8010500D)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspNonblock(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x500E)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspGetcaps(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x8004500F)"), builder_mod.EmitConfig.forExpression());
}

fn genSndctlDspSetfragment(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xC004500A)"), builder_mod.EmitConfig.forExpression());
}
