/// Python _compat_pickle module - Pickle compatibility mappings for Python 2/3
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "n_a_m_e__m_a_p_p_i_n_g", genNameMapping },
    .{ "i_m_p_o_r_t__m_a_p_p_i_n_g", genImportMapping },
    .{ "r_e_v_e_r_s_e__n_a_m_e__m_a_p_p_i_n_g", genReverseNameMapping },
    .{ "r_e_v_e_r_s_e__i_m_p_o_r_t__m_a_p_p_i_n_g", genReverseImportMapping },
});

fn genNameMapping(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genImportMapping(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genReverseNameMapping(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genReverseImportMapping(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}
