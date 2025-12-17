/// Python _ast module - Internal AST support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "py_c_f__o_n_l_y__a_s_t", genPycfOnlyAst },
    .{ "py_c_f__t_y_p_e__c_o_m_m_e_n_t_s", genPycfTypeComments },
    .{ "py_c_f__a_l_l_o_w__t_o_p__l_e_v_e_l__a_w_a_i_t", genPycfAllowToplevelAwait },
});

fn genPycfOnlyAst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x0400)"), builder_mod.EmitConfig.forExpression());
}

fn genPycfTypeComments(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x1000)"), builder_mod.EmitConfig.forExpression());
}

fn genPycfAllowToplevelAwait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 0x2000)"), builder_mod.EmitConfig.forExpression());
}
