/// Python tkinter module - Tk GUI toolkit
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "tk", genTk }, .{ "frame", genFrame }, .{ "label", genLabel }, .{ "button", genButton },
    .{ "entry", genEntry }, .{ "text", genText }, .{ "canvas", genCanvas }, .{ "listbox", genListbox },
    .{ "menu", genMenu }, .{ "menubutton", genMenubutton }, .{ "scrollbar", genScrollbar }, .{ "scale", genScale },
    .{ "spinbox", genSpinbox }, .{ "checkbutton", genCheckbutton }, .{ "radiobutton", genRadiobutton },
    .{ "message", genMessage }, .{ "toplevel", genToplevel }, .{ "paned_window", genPanedWindow },
    .{ "label_frame", genLabelFrame }, .{ "photo_image", genPhotoImage }, .{ "bitmap_image", genBitmapImage },
    .{ "string_var", genStringVar }, .{ "int_var", genIntVar }, .{ "double_var", genDoubleVar },
    .{ "boolean_var", genBooleanVar }, .{ "mainloop", genMainloop }, .{ "tcl_error", genTclError },
    .{ "e_n_d", genEND }, .{ "l_e_f_t", genLEFT }, .{ "r_i_g_h_t", genRIGHT }, .{ "t_o_p", genTOP },
    .{ "b_o_t_t_o_m", genBOTTOM }, .{ "c_e_n_t_e_r", genCENTER }, .{ "n", genN }, .{ "s", genS },
    .{ "e", genE }, .{ "w", genW }, .{ "n_e", genNE }, .{ "n_w", genNW }, .{ "s_e", genSE }, .{ "s_w", genSW },
    .{ "h_o_r_i_z_o_n_t_a_l", genHORIZONTAL }, .{ "v_e_r_t_i_c_a_l", genVERTICAL }, .{ "b_o_t_h", genBOTH },
    .{ "x", genX }, .{ "y", genY }, .{ "n_o_n_e", genNONE }, .{ "r_a_i_s_e_d", genRAISED },
    .{ "s_u_n_k_e_n", genSUNKEN }, .{ "f_l_a_t", genFLAT }, .{ "r_i_d_g_e", genRIDGE },
    .{ "g_r_o_o_v_e", genGROOVE }, .{ "s_o_l_i_d", genSOLID }, .{ "n_o_r_m_a_l", genNORMAL },
    .{ "d_i_s_a_b_l_e_d", genDISABLED }, .{ "a_c_t_i_v_e", genACTIVE }, .{ "h_i_d_d_e_n", genHIDDEN },
    .{ "i_n_s_e_r_t", genINSERT }, .{ "s_e_l", genSEL }, .{ "s_e_l__f_i_r_s_t", genSEL_FIRST },
    .{ "s_e_l__l_a_s_t", genSEL_LAST }, .{ "w_o_r_d", genWORD }, .{ "c_h_a_r", genCHAR },
});

// Helper
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genWidget(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

// Widgets
pub fn genTk(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genLabel(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genButton(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genEntry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genText(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genCanvas(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genListbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genMenu(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genMenubutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genScrollbar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genScale(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genSpinbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genCheckbutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genRadiobutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genToplevel(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genPanedWindow(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genLabelFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genPhotoImage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }
pub fn genBitmapImage(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genWidget(self, args); }

// Variables
pub fn genStringVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = \"\" }"); }
pub fn genIntVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = 0 }"); }
pub fn genDoubleVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = 0.0 }"); }
pub fn genBooleanVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = false }"); }

// Functions
pub fn genMainloop(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
pub fn genTclError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TclError"); }

// String constants
pub fn genEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"end\""); }
pub fn genLEFT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"left\""); }
pub fn genRIGHT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"right\""); }
pub fn genTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"top\""); }
pub fn genBOTTOM(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"bottom\""); }
pub fn genCENTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"center\""); }
pub fn genN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"n\""); }
pub fn genS(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"s\""); }
pub fn genE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"e\""); }
pub fn genW(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"w\""); }
pub fn genNE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ne\""); }
pub fn genNW(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"nw\""); }
pub fn genSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"se\""); }
pub fn genSW(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"sw\""); }
pub fn genHORIZONTAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"horizontal\""); }
pub fn genVERTICAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"vertical\""); }
pub fn genBOTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"both\""); }
pub fn genX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"x\""); }
pub fn genY(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"y\""); }
pub fn genNONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"none\""); }
pub fn genRAISED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"raised\""); }
pub fn genSUNKEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"sunken\""); }
pub fn genFLAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"flat\""); }
pub fn genRIDGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"ridge\""); }
pub fn genGROOVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"groove\""); }
pub fn genSOLID(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"solid\""); }
pub fn genNORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"normal\""); }
pub fn genDISABLED(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"disabled\""); }
pub fn genACTIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"active\""); }
pub fn genHIDDEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"hidden\""); }
pub fn genINSERT(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"insert\""); }
pub fn genSEL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"sel\""); }
pub fn genSEL_FIRST(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"sel.first\""); }
pub fn genSEL_LAST(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"sel.last\""); }
pub fn genWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"word\""); }
pub fn genCHAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"char\""); }
