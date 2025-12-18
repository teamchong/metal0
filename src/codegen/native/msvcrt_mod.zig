/// Python msvcrt module - Windows MSVC runtime routines
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getch", genEmptyStr },
    .{ "getwch", genEmptyStr },
    .{ "getche", genEmptyStr },
    .{ "getwche", genEmptyStr },
    .{ "putch", genVoid },
    .{ "putwch", genVoid },
    .{ "ungetch", genVoid },
    .{ "ungetwch", genVoid },
    .{ "kbhit", genFalse },
    .{ "locking", genVoid },
    .{ "setmode", genZero },
    .{ "heapmin", genVoid },
    .{ "open_osfhandle", genNegOne },
    .{ "get_osfhandle", genNegOne },
    .{ "set_error_mode", genZero },
    .{ "c_r_t__a_s_s_e_m_b_l_y__v_e_r_s_i_o_n", genEmptyStr },
    .{ "l_k__n_b_l_c_k", gen2 },
    .{ "l_k__n_b_r_l_c_k", gen4 },
    .{ "l_k__l_o_c_k", gen1 },
    .{ "l_k__r_l_c_k", gen3 },
    .{ "l_k__u_n_l_c_k", genZero },
    .{ "s_e_m__f_a_i_l_c_r_i_t_i_c_a_l_e_r_r_o_r_s", gen1 },
    .{ "s_e_m__n_o_a_l_i_g_n_m_e_n_t_f_a_u_l_t_e_x_c_e_p_t", gen4 },
    .{ "s_e_m__n_o_g_p_f_a_u_l_t_e_r_r_o_r_b_o_x", gen2 },
    .{ "s_e_m__n_o_o_p_e_n_f_i_l_e_e_r_r_o_r_b_o_x", genHex8000 },
});

fn genEmptyStr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genVoid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genFalse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genZero(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genNegOne(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-1), builder_mod.EmitConfig.forExpression());
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

fn genHex8000(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("0x8000"), builder_mod.EmitConfig.forExpression());
}
