/// Python msvcrt module - Windows MSVC runtime routines
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0"); }
fn genNeg1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-1"); }
fn genI1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "1"); }
fn genI2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn genI3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "3"); }
fn genI4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
fn genHex8000(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x8000"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "getch", genEmptyStr }, .{ "getwch", genEmptyStr }, .{ "getche", genEmptyStr }, .{ "getwche", genEmptyStr },
    .{ "putch", genUnit }, .{ "putwch", genUnit }, .{ "ungetch", genUnit }, .{ "ungetwch", genUnit },
    .{ "kbhit", genFalse }, .{ "locking", genUnit }, .{ "setmode", genZero }, .{ "heapmin", genUnit },
    .{ "open_osfhandle", genNeg1 }, .{ "get_osfhandle", genNeg1 }, .{ "set_error_mode", genZero },
    .{ "c_r_t__a_s_s_e_m_b_l_y__v_e_r_s_i_o_n", genEmptyStr },
    .{ "l_k__n_b_l_c_k", genI2 }, .{ "l_k__n_b_r_l_c_k", genI4 }, .{ "l_k__l_o_c_k", genI1 }, .{ "l_k__r_l_c_k", genI3 }, .{ "l_k__u_n_l_c_k", genZero },
    .{ "s_e_m__f_a_i_l_c_r_i_t_i_c_a_l_e_r_r_o_r_s", genI1 }, .{ "s_e_m__n_o_a_l_i_g_n_m_e_n_t_f_a_u_l_t_e_x_c_e_p_t", genI4 },
    .{ "s_e_m__n_o_g_p_f_a_u_l_t_e_r_r_o_r_b_o_x", genI2 }, .{ "s_e_m__n_o_o_p_e_n_f_i_l_e_e_r_r_o_r_b_o_x", genHex8000 },
});
