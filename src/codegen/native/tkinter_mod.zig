/// Python tkinter module - Tk GUI toolkit
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Widgets (all emit .{})
    .{ "tk", genConst(".{}") }, .{ "frame", genConst(".{}") }, .{ "label", genConst(".{}") }, .{ "button", genConst(".{}") },
    .{ "entry", genConst(".{}") }, .{ "text", genConst(".{}") }, .{ "canvas", genConst(".{}") }, .{ "listbox", genConst(".{}") },
    .{ "menu", genConst(".{}") }, .{ "menubutton", genConst(".{}") }, .{ "scrollbar", genConst(".{}") }, .{ "scale", genConst(".{}") },
    .{ "spinbox", genConst(".{}") }, .{ "checkbutton", genConst(".{}") }, .{ "radiobutton", genConst(".{}") },
    .{ "message", genConst(".{}") }, .{ "toplevel", genConst(".{}") }, .{ "paned_window", genConst(".{}") },
    .{ "label_frame", genConst(".{}") }, .{ "photo_image", genConst(".{}") }, .{ "bitmap_image", genConst(".{}") },
    // Variables
    .{ "string_var", genConst(".{ .value = \"\" }") }, .{ "int_var", genConst(".{ .value = 0 }") },
    .{ "double_var", genConst(".{ .value = 0.0 }") }, .{ "boolean_var", genConst(".{ .value = false }") },
    // Functions
    .{ "mainloop", genConst("{}") }, .{ "tcl_error", genConst("error.TclError") },
    // Constants
    .{ "e_n_d", genConst("\"end\"") }, .{ "l_e_f_t", genConst("\"left\"") }, .{ "r_i_g_h_t", genConst("\"right\"") }, .{ "t_o_p", genConst("\"top\"") },
    .{ "b_o_t_t_o_m", genConst("\"bottom\"") }, .{ "c_e_n_t_e_r", genConst("\"center\"") },
    .{ "n", genConst("\"n\"") }, .{ "s", genConst("\"s\"") }, .{ "e", genConst("\"e\"") }, .{ "w", genConst("\"w\"") },
    .{ "n_e", genConst("\"ne\"") }, .{ "n_w", genConst("\"nw\"") }, .{ "s_e", genConst("\"se\"") }, .{ "s_w", genConst("\"sw\"") },
    .{ "h_o_r_i_z_o_n_t_a_l", genConst("\"horizontal\"") }, .{ "v_e_r_t_i_c_a_l", genConst("\"vertical\"") }, .{ "b_o_t_h", genConst("\"both\"") },
    .{ "x", genConst("\"x\"") }, .{ "y", genConst("\"y\"") }, .{ "n_o_n_e", genConst("\"none\"") },
    .{ "r_a_i_s_e_d", genConst("\"raised\"") }, .{ "s_u_n_k_e_n", genConst("\"sunken\"") }, .{ "f_l_a_t", genConst("\"flat\"") },
    .{ "r_i_d_g_e", genConst("\"ridge\"") }, .{ "g_r_o_o_v_e", genConst("\"groove\"") }, .{ "s_o_l_i_d", genConst("\"solid\"") },
    .{ "n_o_r_m_a_l", genConst("\"normal\"") }, .{ "d_i_s_a_b_l_e_d", genConst("\"disabled\"") }, .{ "a_c_t_i_v_e", genConst("\"active\"") }, .{ "h_i_d_d_e_n", genConst("\"hidden\"") },
    .{ "i_n_s_e_r_t", genConst("\"insert\"") }, .{ "s_e_l", genConst("\"sel\"") }, .{ "s_e_l__f_i_r_s_t", genConst("\"sel.first\"") }, .{ "s_e_l__l_a_s_t", genConst("\"sel.last\"") },
    .{ "w_o_r_d", genConst("\"word\"") }, .{ "c_h_a_r", genConst("\"char\"") },
});
