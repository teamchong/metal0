/// Python _msi module - Windows MSI database access
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open_database", genOpenDatabase },
    .{ "create_record", genCreateRecord },
    .{ "uuid_create", genUuidCreate },
    .{ "f_c_i_create", genFciCreate },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", genMsidbOpenReadonly },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", genMsidbOpenTransact },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", genMsidbOpenCreate },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", genMsidbOpenCreatedirect },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", genMsidbOpenDirect },
    .{ "p_i_d__c_o_d_e_p_a_g_e", genPidCodepage },
    .{ "p_i_d__t_i_t_l_e", genPidTitle },
    .{ "p_i_d__s_u_b_j_e_c_t", genPidSubject },
    .{ "p_i_d__a_u_t_h_o_r", genPidAuthor },
    .{ "p_i_d__k_e_y_w_o_r_d_s", genPidKeywords },
    .{ "p_i_d__c_o_m_m_e_n_t_s", genPidComments },
    .{ "p_i_d__t_e_m_p_l_a_t_e", genPidTemplate },
    .{ "p_i_d__r_e_v_n_u_m_b_e_r", genPidRevnumber },
    .{ "p_i_d__p_a_g_e_c_o_u_n_t", genPidPagecount },
    .{ "p_i_d__w_o_r_d_c_o_u_n_t", genPidWordcount },
    .{ "p_i_d__a_p_p_n_a_m_e", genPidAppname },
    .{ "p_i_d__s_e_c_u_r_i_t_y", genPidSecurity },
});

fn genOpenDatabase(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCreateRecord(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genUuidCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("00000000-0000-0000-0000-000000000000"), builder_mod.EmitConfig.forExpression());
}

fn genFciCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genMsidbOpenReadonly(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genMsidbOpenTransact(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genMsidbOpenCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genMsidbOpenCreatedirect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genMsidbOpenDirect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genPidCodepage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genPidTitle(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genPidSubject(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genPidAuthor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genPidKeywords(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genPidComments(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(6), builder_mod.EmitConfig.forExpression());
}

fn genPidTemplate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(7), builder_mod.EmitConfig.forExpression());
}

fn genPidRevnumber(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(9), builder_mod.EmitConfig.forExpression());
}

fn genPidPagecount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(14), builder_mod.EmitConfig.forExpression());
}

fn genPidWordcount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(15), builder_mod.EmitConfig.forExpression());
}

fn genPidAppname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(18), builder_mod.EmitConfig.forExpression());
}

fn genPidSecurity(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(19), builder_mod.EmitConfig.forExpression());
}

