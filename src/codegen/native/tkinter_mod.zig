/// Python tkinter module - Tk GUI toolkit
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
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
    .{ "e_n_d", genEND },
    .{ "l_e_f_t", genLEFT },
    .{ "r_i_g_h_t", genRIGHT },
    .{ "t_o_p", genTOP },
    .{ "b_o_t_t_o_m", genBOTTOM },
    .{ "c_e_n_t_e_r", genCENTER },
    .{ "n", genN },
    .{ "s", genS },
    .{ "e", genE },
    .{ "w", genW },
    .{ "n_e", genNE },
    .{ "n_w", genNW },
    .{ "s_e", genSE },
    .{ "s_w", genSW },
    .{ "h_o_r_i_z_o_n_t_a_l", genHORIZONTAL },
    .{ "v_e_r_t_i_c_a_l", genVERTICAL },
    .{ "b_o_t_h", genBOTH },
    .{ "x", genX },
    .{ "y", genY },
    .{ "n_o_n_e", genNONE },
    .{ "r_a_i_s_e_d", genRAISED },
    .{ "s_u_n_k_e_n", genSUNKEN },
    .{ "f_l_a_t", genFLAT },
    .{ "r_i_d_g_e", genRIDGE },
    .{ "g_r_o_o_v_e", genGROOVE },
    .{ "s_o_l_i_d", genSOLID },
    .{ "n_o_r_m_a_l", genNORMAL },
    .{ "d_i_s_a_b_l_e_d", genDISABLED },
    .{ "a_c_t_i_v_e", genACTIVE },
    .{ "h_i_d_d_e_n", genHIDDEN },
    .{ "i_n_s_e_r_t", genINSERT },
    .{ "s_e_l", genSEL },
    .{ "s_e_l__f_i_r_s_t", genSEL_FIRST },
    .{ "s_e_l__l_a_s_t", genSEL_LAST },
    .{ "w_o_r_d", genWORD },
    .{ "c_h_a_r", genCHAR },
});

/// Generate tkinter.Tk() - Create main window
pub fn genTk(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Frame(parent) - Create frame widget
pub fn genFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Label(parent, text=...) - Create label widget
pub fn genLabel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Button(parent, text=..., command=...) - Create button widget
pub fn genButton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Entry(parent) - Create text entry widget
pub fn genEntry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Text(parent) - Create multi-line text widget
pub fn genText(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Canvas(parent) - Create canvas widget
pub fn genCanvas(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Listbox(parent) - Create listbox widget
pub fn genListbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Menu(parent) - Create menu widget
pub fn genMenu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Menubutton(parent) - Create menubutton widget
pub fn genMenubutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Scrollbar(parent) - Create scrollbar widget
pub fn genScrollbar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Scale(parent) - Create scale widget
pub fn genScale(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Spinbox(parent) - Create spinbox widget
pub fn genSpinbox(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Checkbutton(parent) - Create checkbutton widget
pub fn genCheckbutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Radiobutton(parent) - Create radiobutton widget
pub fn genRadiobutton(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Message(parent) - Create message widget
pub fn genMessage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.Toplevel(parent) - Create toplevel window
pub fn genToplevel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.PanedWindow(parent) - Create paned window
pub fn genPanedWindow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.LabelFrame(parent) - Create labeled frame
pub fn genLabelFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.PhotoImage(file=...) - Create photo image
pub fn genPhotoImage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.BitmapImage(file=...) - Create bitmap image
pub fn genBitmapImage(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate tkinter.StringVar() - Create string variable
pub fn genStringVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = \"\" }");
}

/// Generate tkinter.IntVar() - Create integer variable
pub fn genIntVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = 0 }");
}

/// Generate tkinter.DoubleVar() - Create double variable
pub fn genDoubleVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = 0.0 }");
}

/// Generate tkinter.BooleanVar() - Create boolean variable
pub fn genBooleanVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .value = false }");
}

/// Generate tkinter.mainloop() - Run event loop
pub fn genMainloop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate tkinter.TclError exception
pub fn genTclError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TclError");
}

/// Generate tkinter.END constant
pub fn genEND(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"end\"");
}

/// Generate tkinter.LEFT constant
pub fn genLEFT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"left\"");
}

/// Generate tkinter.RIGHT constant
pub fn genRIGHT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"right\"");
}

/// Generate tkinter.TOP constant
pub fn genTOP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"top\"");
}

/// Generate tkinter.BOTTOM constant
pub fn genBOTTOM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"bottom\"");
}

/// Generate tkinter.CENTER constant
pub fn genCENTER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"center\"");
}

/// Generate tkinter.N constant
pub fn genN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"n\"");
}

/// Generate tkinter.S constant
pub fn genS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"s\"");
}

/// Generate tkinter.E constant
pub fn genE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"e\"");
}

/// Generate tkinter.W constant
pub fn genW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"w\"");
}

/// Generate tkinter.NE constant
pub fn genNE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ne\"");
}

/// Generate tkinter.NW constant
pub fn genNW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"nw\"");
}

/// Generate tkinter.SE constant
pub fn genSE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"se\"");
}

/// Generate tkinter.SW constant
pub fn genSW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"sw\"");
}

/// Generate tkinter.HORIZONTAL constant
pub fn genHORIZONTAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"horizontal\"");
}

/// Generate tkinter.VERTICAL constant
pub fn genVERTICAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"vertical\"");
}

/// Generate tkinter.BOTH constant
pub fn genBOTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"both\"");
}

/// Generate tkinter.X constant
pub fn genX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"x\"");
}

/// Generate tkinter.Y constant
pub fn genY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"y\"");
}

/// Generate tkinter.NONE constant
pub fn genNONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"none\"");
}

/// Generate tkinter.RAISED constant
pub fn genRAISED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"raised\"");
}

/// Generate tkinter.SUNKEN constant
pub fn genSUNKEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"sunken\"");
}

/// Generate tkinter.FLAT constant
pub fn genFLAT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"flat\"");
}

/// Generate tkinter.RIDGE constant
pub fn genRIDGE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ridge\"");
}

/// Generate tkinter.GROOVE constant
pub fn genGROOVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"groove\"");
}

/// Generate tkinter.SOLID constant
pub fn genSOLID(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"solid\"");
}

/// Generate tkinter.NORMAL constant
pub fn genNORMAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"normal\"");
}

/// Generate tkinter.DISABLED constant
pub fn genDISABLED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"disabled\"");
}

/// Generate tkinter.ACTIVE constant
pub fn genACTIVE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"active\"");
}

/// Generate tkinter.HIDDEN constant
pub fn genHIDDEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"hidden\"");
}

/// Generate tkinter.INSERT constant
pub fn genINSERT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"insert\"");
}

/// Generate tkinter.SEL constant
pub fn genSEL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"sel\"");
}

/// Generate tkinter.SEL_FIRST constant
pub fn genSEL_FIRST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"sel.first\"");
}

/// Generate tkinter.SEL_LAST constant
pub fn genSEL_LAST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"sel.last\"");
}

/// Generate tkinter.WORD constant
pub fn genWORD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"word\"");
}

/// Generate tkinter.CHAR constant
pub fn genCHAR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"char\"");
}
