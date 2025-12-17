/// Python _symtable module - Internal symtable support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "symtable", genSymtable },
    .{ "s_c_o_p_e__o_f_f", genScopeOff },
    .{ "s_c_o_p_e__m_a_s_k", genScopeMask },
    .{ "l_o_c_a_l", genLocal },
    .{ "g_l_o_b_a_l__e_x_p_l_i_c_i_t", genGlobalExplicit },
    .{ "g_l_o_b_a_l__i_m_p_l_i_c_i_t", genGlobalImplicit },
    .{ "f_r_e_e", genFree },
    .{ "c_e_l_l", genCell },
    .{ "t_y_p_e__f_u_n_c_t_i_o_n", genTypeFunction },
    .{ "t_y_p_e__c_l_a_s_s", genTypeClass },
    .{ "t_y_p_e__m_o_d_u_l_e", genTypeModule },
});

fn genSymtable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"top\", .type = \"module\", .id = 0, .lineno = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genScopeOff(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(11), builder_mod.EmitConfig.forExpression());
}

fn genScopeMask(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0xf)"), builder_mod.EmitConfig.forExpression());
}

fn genLocal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genGlobalExplicit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genGlobalImplicit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genFree(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genCell(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genTypeFunction(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genTypeClass(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genTypeModule(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

