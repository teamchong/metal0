/// Python msvcrt module - Windows MSVC runtime routines
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getch", genConst("\"\"") }, .{ "getwch", genConst("\"\"") }, .{ "getche", genConst("\"\"") }, .{ "getwche", genConst("\"\"") },
    .{ "putch", genConst("{}") }, .{ "putwch", genConst("{}") }, .{ "ungetch", genConst("{}") }, .{ "ungetwch", genConst("{}") },
    .{ "kbhit", genConst("false") }, .{ "locking", genConst("{}") }, .{ "setmode", genConst("0") }, .{ "heapmin", genConst("{}") },
    .{ "open_osfhandle", genConst("-1") }, .{ "get_osfhandle", genConst("-1") }, .{ "set_error_mode", genConst("0") },
    .{ "c_r_t__a_s_s_e_m_b_l_y__v_e_r_s_i_o_n", genConst("\"\"") },
    .{ "l_k__n_b_l_c_k", genConst("2") }, .{ "l_k__n_b_r_l_c_k", genConst("4") },
    .{ "l_k__l_o_c_k", genConst("1") }, .{ "l_k__r_l_c_k", genConst("3") }, .{ "l_k__u_n_l_c_k", genConst("0") },
    .{ "s_e_m__f_a_i_l_c_r_i_t_i_c_a_l_e_r_r_o_r_s", genConst("1") },
    .{ "s_e_m__n_o_a_l_i_g_n_m_e_n_t_f_a_u_l_t_e_x_c_e_p_t", genConst("4") },
    .{ "s_e_m__n_o_g_p_f_a_u_l_t_e_r_r_o_r_b_o_x", genConst("2") },
    .{ "s_e_m__n_o_o_p_e_n_f_i_l_e_e_r_r_o_r_b_o_x", genConst("0x8000") },
});
