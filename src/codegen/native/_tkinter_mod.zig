/// Python _tkinter module - Tcl/Tk interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "create", genConst(".{}") }, .{ "setbusywaitinterval", genConst("{}") }, .{ "getbusywaitinterval", genConst("20") },
    .{ "tcl_error", genConst("error.TclError") }, .{ "t_k__v_e_r_s_i_o_n", genConst("\"8.6\"") }, .{ "t_c_l__v_e_r_s_i_o_n", genConst("\"8.6\"") },
    .{ "r_e_a_d_a_b_l_e", genConst("2") }, .{ "w_r_i_t_a_b_l_e", genConst("4") }, .{ "e_x_c_e_p_t_i_o_n", genConst("8") },
    .{ "d_o_n_t__w_a_i_t", genConst("2") }, .{ "w_i_n_d_o_w__e_v_e_n_t_s", genConst("4") }, .{ "f_i_l_e__e_v_e_n_t_s", genConst("8") },
    .{ "t_i_m_e_r__e_v_e_n_t_s", genConst("16") }, .{ "i_d_l_e__e_v_e_n_t_s", genConst("32") }, .{ "a_l_l__e_v_e_n_t_s", genConst("-3") },
});
