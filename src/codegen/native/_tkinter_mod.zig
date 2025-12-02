/// Python _tkinter module - Tcl/Tk interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "create", genEmpty }, .{ "setbusywaitinterval", genUnit }, .{ "getbusywaitinterval", genI20 },
    .{ "tcl_error", genErr }, .{ "t_k__v_e_r_s_i_o_n", genVer }, .{ "t_c_l__v_e_r_s_i_o_n", genVer },
    .{ "r_e_a_d_a_b_l_e", genI2 }, .{ "w_r_i_t_a_b_l_e", genI4 }, .{ "e_x_c_e_p_t_i_o_n", genI8 },
    .{ "d_o_n_t__w_a_i_t", genI2 }, .{ "w_i_n_d_o_w__e_v_e_n_t_s", genI4 }, .{ "f_i_l_e__e_v_e_n_t_s", genI8 },
    .{ "t_i_m_e_r__e_v_e_n_t_s", genI16 }, .{ "i_d_l_e__e_v_e_n_t_s", genI32 }, .{ "a_l_l__e_v_e_n_t_s", genIN3 },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genErr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TclError"); }
fn genVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"8.6\""); }
fn genI2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "2"); }
fn genI4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "4"); }
fn genI8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "8"); }
fn genI16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "16"); }
fn genI20(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "20"); }
fn genI32(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "32"); }
fn genIN3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "-3"); }
