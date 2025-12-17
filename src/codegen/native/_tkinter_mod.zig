/// Python _tkinter module - Tcl/Tk interface
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "create", genCreate },
    .{ "setbusywaitinterval", genSetbusywaitinterval },
    .{ "getbusywaitinterval", genGetbusywaitinterval },
    .{ "tcl_error", genTclError },
    .{ "t_k__v_e_r_s_i_o_n", genTkVersion },
    .{ "t_c_l__v_e_r_s_i_o_n", genTclVersion },
    .{ "r_e_a_d_a_b_l_e", genReadable },
    .{ "w_r_i_t_a_b_l_e", genWritable },
    .{ "e_x_c_e_p_t_i_o_n", genException },
    .{ "d_o_n_t__w_a_i_t", genDontWait },
    .{ "w_i_n_d_o_w__e_v_e_n_t_s", genWindowEvents },
    .{ "f_i_l_e__e_v_e_n_t_s", genFileEvents },
    .{ "t_i_m_e_r__e_v_e_n_t_s", genTimerEvents },
    .{ "i_d_l_e__e_v_e_n_t_s", genIdleEvents },
    .{ "a_l_l__e_v_e_n_t_s", genAllEvents },
});

fn genCreate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetbusywaitinterval(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetbusywaitinterval(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(20), builder_mod.EmitConfig.forExpression());
}

fn genTclError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.TclError"), builder_mod.EmitConfig.forExpression());
}

fn genTkVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("8.6"), builder_mod.EmitConfig.forExpression());
}

fn genTclVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("8.6"), builder_mod.EmitConfig.forExpression());
}

fn genReadable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genWritable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genDontWait(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genWindowEvents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genFileEvents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genTimerEvents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genIdleEvents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32), builder_mod.EmitConfig.forExpression());
}

fn genAllEvents(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-3), builder_mod.EmitConfig.forExpression());
}

