/// Python msilib module - Windows MSI file creation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "init_database", genEmptyStruct },
    .{ "add_data", genVoid },
    .{ "add_tables", genVoid },
    .{ "add_stream", genVoid },
    .{ "gen_uuid", genUuid },
    .{ "open_database", genEmptyStruct },
    .{ "create_record", genEmptyStruct },
    .{ "c_a_b", genEmptyStruct },
    .{ "directory", genEmptyStruct },
    .{ "feature", genEmptyStruct },
    .{ "dialog", genEmptyStruct },
    .{ "control", genEmptyStruct },
    .{ "radio_button_group", genEmptyStruct },
    .{ "a_m_d64", genFalse },
    .{ "win64", genFalse },
    .{ "itanium", genFalse },
    .{ "schema", genEmptyStruct },
    .{ "sequence", genEmptyStruct },
    .{ "text", genEmptyStruct },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e_d_i_r_e_c_t", gen4 },
    .{ "m_s_i_d_b_o_p_e_n__c_r_e_a_t_e", gen3 },
    .{ "m_s_i_d_b_o_p_e_n__d_i_r_e_c_t", gen2 },
    .{ "m_s_i_d_b_o_p_e_n__r_e_a_d_o_n_l_y", gen0 },
    .{ "m_s_i_d_b_o_p_e_n__t_r_a_n_s_a_c_t", gen1 },
});

fn genEmptyStruct(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genVoid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUuid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("{00000000-0000-0000-0000-000000000000}"), builder_mod.EmitConfig.forExpression());
}

fn genFalse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn gen0(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn gen1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn gen2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn gen3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn gen4(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}
