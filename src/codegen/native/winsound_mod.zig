/// Python winsound module - Windows sound playing interface
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "beep", genBeep },
    .{ "play_sound", genPlaySound },
    .{ "message_beep", genMessageBeep },
    .{ "s_n_d__f_i_l_e_n_a_m_e", genSndFilename },
    .{ "s_n_d__a_l_i_a_s", genSndAlias },
    .{ "s_n_d__l_o_o_p", genSndLoop },
    .{ "s_n_d__m_e_m_o_r_y", genSndMemory },
    .{ "s_n_d__p_u_r_g_e", genSndPurge },
    .{ "s_n_d__a_s_y_n_c", genSndAsync },
    .{ "s_n_d__n_o_d_e_f_a_u_l_t", genSndNodefault },
    .{ "s_n_d__n_o_s_t_o_p", genSndNostop },
    .{ "s_n_d__n_o_w_a_i_t", genSndNowait },
    .{ "m_b__i_c_o_n_a_s_t_e_r_i_s_k", genMbIconasterisk },
    .{ "m_b__i_c_o_n_e_x_c_l_a_m_a_t_i_o_n", genMbIconexclamation },
    .{ "m_b__i_c_o_n_h_a_n_d", genMbIconhand },
    .{ "m_b__i_c_o_n_q_u_e_s_t_i_o_n", genMbIconquestion },
    .{ "m_b__o_k", genMbOk },
});

fn genBeep(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPlaySound(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genMessageBeep(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genSndFilename(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x20000"), builder_mod.EmitConfig.forExpression());
}

fn genSndAlias(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x10000"), builder_mod.EmitConfig.forExpression());
}

fn genSndLoop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0008"), builder_mod.EmitConfig.forExpression());
}

fn genSndMemory(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0004"), builder_mod.EmitConfig.forExpression());
}

fn genSndPurge(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0040"), builder_mod.EmitConfig.forExpression());
}

fn genSndAsync(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0001"), builder_mod.EmitConfig.forExpression());
}

fn genSndNodefault(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0002"), builder_mod.EmitConfig.forExpression());
}

fn genSndNostop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0010"), builder_mod.EmitConfig.forExpression());
}

fn genSndNowait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x2000"), builder_mod.EmitConfig.forExpression());
}

fn genMbIconasterisk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x40"), builder_mod.EmitConfig.forExpression());
}

fn genMbIconexclamation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x30"), builder_mod.EmitConfig.forExpression());
}

fn genMbIconhand(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x10"), builder_mod.EmitConfig.forExpression());
}

fn genMbIconquestion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x20"), builder_mod.EmitConfig.forExpression());
}

fn genMbOk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x0"), builder_mod.EmitConfig.forExpression());
}
