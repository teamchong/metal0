/// Python tkinter module - Tk GUI toolkit
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genWidget(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genStr(comptime s: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"" ++ s ++ "\""); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Widgets (all emit .{})
    .{ "tk", genWidget }, .{ "frame", genWidget }, .{ "label", genWidget }, .{ "button", genWidget },
    .{ "entry", genWidget }, .{ "text", genWidget }, .{ "canvas", genWidget }, .{ "listbox", genWidget },
    .{ "menu", genWidget }, .{ "menubutton", genWidget }, .{ "scrollbar", genWidget }, .{ "scale", genWidget },
    .{ "spinbox", genWidget }, .{ "checkbutton", genWidget }, .{ "radiobutton", genWidget },
    .{ "message", genWidget }, .{ "toplevel", genWidget }, .{ "paned_window", genWidget },
    .{ "label_frame", genWidget }, .{ "photo_image", genWidget }, .{ "bitmap_image", genWidget },
    // Variables
    .{ "string_var", genStringVar }, .{ "int_var", genIntVar }, .{ "double_var", genDoubleVar }, .{ "boolean_var", genBooleanVar },
    // Functions
    .{ "mainloop", genUnit }, .{ "tcl_error", genTclError },
    // Constants
    .{ "e_n_d", genStr("end") }, .{ "l_e_f_t", genStr("left") }, .{ "r_i_g_h_t", genStr("right") }, .{ "t_o_p", genStr("top") },
    .{ "b_o_t_t_o_m", genStr("bottom") }, .{ "c_e_n_t_e_r", genStr("center") },
    .{ "n", genStr("n") }, .{ "s", genStr("s") }, .{ "e", genStr("e") }, .{ "w", genStr("w") },
    .{ "n_e", genStr("ne") }, .{ "n_w", genStr("nw") }, .{ "s_e", genStr("se") }, .{ "s_w", genStr("sw") },
    .{ "h_o_r_i_z_o_n_t_a_l", genStr("horizontal") }, .{ "v_e_r_t_i_c_a_l", genStr("vertical") }, .{ "b_o_t_h", genStr("both") },
    .{ "x", genStr("x") }, .{ "y", genStr("y") }, .{ "n_o_n_e", genStr("none") },
    .{ "r_a_i_s_e_d", genStr("raised") }, .{ "s_u_n_k_e_n", genStr("sunken") }, .{ "f_l_a_t", genStr("flat") },
    .{ "r_i_d_g_e", genStr("ridge") }, .{ "g_r_o_o_v_e", genStr("groove") }, .{ "s_o_l_i_d", genStr("solid") },
    .{ "n_o_r_m_a_l", genStr("normal") }, .{ "d_i_s_a_b_l_e_d", genStr("disabled") }, .{ "a_c_t_i_v_e", genStr("active") }, .{ "h_i_d_d_e_n", genStr("hidden") },
    .{ "i_n_s_e_r_t", genStr("insert") }, .{ "s_e_l", genStr("sel") }, .{ "s_e_l__f_i_r_s_t", genStr("sel.first") }, .{ "s_e_l__l_a_s_t", genStr("sel.last") },
    .{ "w_o_r_d", genStr("word") }, .{ "c_h_a_r", genStr("char") },
});

fn genStringVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = \"\" }"); }
fn genIntVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = 0 }"); }
fn genDoubleVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = 0.0 }"); }
fn genBooleanVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .value = false }"); }
fn genTclError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TclError"); }
