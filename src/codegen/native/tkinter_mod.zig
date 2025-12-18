/// Python tkinter module - Tk GUI toolkit
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "tk", genTk },
    .{ "frame", genFrame },
    .{ "label", genLabel },
    .{ "button", genButton },
    .{ "entry", genEntry },
    .{ "text", genText },
    .{ "canvas", genCanvas },
    .{ "listbox", genListbox },
    .{ "menu", genMenu },
    .{ "menubutton", genMenubutton },
    .{ "scrollbar", genScrollbar },
    .{ "scale", genScale },
    .{ "spinbox", genSpinbox },
    .{ "checkbutton", genCheckbutton },
    .{ "radiobutton", genRadiobutton },
    .{ "message", genMessage },
    .{ "toplevel", genToplevel },
    .{ "paned_window", genPanedWindow },
    .{ "label_frame", genLabelFrame },
    .{ "photo_image", genPhotoImage },
    .{ "bitmap_image", genBitmapImage },
    .{ "string_var", genStringVar },
    .{ "int_var", genIntVar },
    .{ "double_var", genDoubleVar },
    .{ "boolean_var", genBooleanVar },
    .{ "mainloop", genMainloop },
    .{ "tcl_error", genTclError },
    .{ "e_n_d", genEnd },
    .{ "l_e_f_t", genLeft },
    .{ "r_i_g_h_t", genRight },
    .{ "t_o_p", genTop },
    .{ "b_o_t_t_o_m", genBottom },
    .{ "c_e_n_t_e_r", genCenter },
    .{ "n", genN },
    .{ "s", genS },
    .{ "e", genE },
    .{ "w", genW },
    .{ "n_e", genNE },
    .{ "n_w", genNW },
    .{ "s_e", genSE },
    .{ "s_w", genSW },
    .{ "h_o_r_i_z_o_n_t_a_l", genHorizontal },
    .{ "v_e_r_t_i_c_a_l", genVertical },
    .{ "b_o_t_h", genBoth },
    .{ "x", genX },
    .{ "y", genY },
    .{ "n_o_n_e", genNone },
    .{ "r_a_i_s_e_d", genRaised },
    .{ "s_u_n_k_e_n", genSunken },
    .{ "f_l_a_t", genFlat },
    .{ "r_i_d_g_e", genRidge },
    .{ "g_r_o_o_v_e", genGroove },
    .{ "s_o_l_i_d", genSolid },
    .{ "n_o_r_m_a_l", genNormal },
    .{ "d_i_s_a_b_l_e_d", genDisabled },
    .{ "a_c_t_i_v_e", genActive },
    .{ "h_i_d_d_e_n", genHidden },
    .{ "i_n_s_e_r_t", genInsert },
    .{ "s_e_l", genSel },
    .{ "s_e_l__f_i_r_s_t", genSelFirst },
    .{ "s_e_l__l_a_s_t", genSelLast },
    .{ "w_o_r_d", genWord },
    .{ "c_h_a_r", genChar },
});

fn genTk(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genFrame(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genLabel(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genButton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genEntry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genText(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCanvas(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genListbox(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genMenu(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genMenubutton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genScrollbar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genScale(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genSpinbox(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCheckbutton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genRadiobutton(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genMessage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genToplevel(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genPanedWindow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genLabelFrame(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genPhotoImage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genBitmapImage(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genStringVar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genIntVar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genDoubleVar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = 0.0 }"), builder_mod.EmitConfig.forExpression());
}

fn genBooleanVar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .value = false }"), builder_mod.EmitConfig.forExpression());
}

fn genMainloop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTclError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.TclError"), builder_mod.EmitConfig.forExpression());
}

fn genEnd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("end"), builder_mod.EmitConfig.forExpression());
}

fn genLeft(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("left"), builder_mod.EmitConfig.forExpression());
}

fn genRight(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("right"), builder_mod.EmitConfig.forExpression());
}

fn genTop(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("top"), builder_mod.EmitConfig.forExpression());
}

fn genBottom(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("bottom"), builder_mod.EmitConfig.forExpression());
}

fn genCenter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("center"), builder_mod.EmitConfig.forExpression());
}

fn genN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("n"), builder_mod.EmitConfig.forExpression());
}

fn genS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("s"), builder_mod.EmitConfig.forExpression());
}

fn genE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("e"), builder_mod.EmitConfig.forExpression());
}

fn genW(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("w"), builder_mod.EmitConfig.forExpression());
}

fn genNE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ne"), builder_mod.EmitConfig.forExpression());
}

fn genNW(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("nw"), builder_mod.EmitConfig.forExpression());
}

fn genSE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("se"), builder_mod.EmitConfig.forExpression());
}

fn genSW(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("sw"), builder_mod.EmitConfig.forExpression());
}

fn genHorizontal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("horizontal"), builder_mod.EmitConfig.forExpression());
}

fn genVertical(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("vertical"), builder_mod.EmitConfig.forExpression());
}

fn genBoth(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("both"), builder_mod.EmitConfig.forExpression());
}

fn genX(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("x"), builder_mod.EmitConfig.forExpression());
}

fn genY(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("y"), builder_mod.EmitConfig.forExpression());
}

fn genNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("none"), builder_mod.EmitConfig.forExpression());
}

fn genRaised(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("raised"), builder_mod.EmitConfig.forExpression());
}

fn genSunken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("sunken"), builder_mod.EmitConfig.forExpression());
}

fn genFlat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("flat"), builder_mod.EmitConfig.forExpression());
}

fn genRidge(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ridge"), builder_mod.EmitConfig.forExpression());
}

fn genGroove(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("groove"), builder_mod.EmitConfig.forExpression());
}

fn genSolid(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("solid"), builder_mod.EmitConfig.forExpression());
}

fn genNormal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("normal"), builder_mod.EmitConfig.forExpression());
}

fn genDisabled(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("disabled"), builder_mod.EmitConfig.forExpression());
}

fn genActive(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("active"), builder_mod.EmitConfig.forExpression());
}

fn genHidden(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("hidden"), builder_mod.EmitConfig.forExpression());
}

fn genInsert(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("insert"), builder_mod.EmitConfig.forExpression());
}

fn genSel(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("sel"), builder_mod.EmitConfig.forExpression());
}

fn genSelFirst(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("sel.first"), builder_mod.EmitConfig.forExpression());
}

fn genSelLast(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("sel.last"), builder_mod.EmitConfig.forExpression());
}

fn genWord(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("word"), builder_mod.EmitConfig.forExpression());
}

fn genChar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("char"), builder_mod.EmitConfig.forExpression());
}
