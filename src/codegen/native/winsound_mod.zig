/// Python winsound module - Windows sound playing interface
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "beep", genUnit }, .{ "play_sound", genUnit }, .{ "message_beep", genUnit },
    .{ "s_n_d__f_i_l_e_n_a_m_e", genSndFile }, .{ "s_n_d__a_l_i_a_s", genSndAlias }, .{ "s_n_d__l_o_o_p", genSndLoop },
    .{ "s_n_d__m_e_m_o_r_y", genSndMem }, .{ "s_n_d__p_u_r_g_e", genSndPurge }, .{ "s_n_d__a_s_y_n_c", genSndAsync },
    .{ "s_n_d__n_o_d_e_f_a_u_l_t", genSndNoDef }, .{ "s_n_d__n_o_s_t_o_p", genSndNoStop }, .{ "s_n_d__n_o_w_a_i_t", genSndNoWait },
    .{ "m_b__i_c_o_n_a_s_t_e_r_i_s_k", genMbAst }, .{ "m_b__i_c_o_n_e_x_c_l_a_m_a_t_i_o_n", genMbExc },
    .{ "m_b__i_c_o_n_h_a_n_d", genMbHand }, .{ "m_b__i_c_o_n_q_u_e_s_t_i_o_n", genMbQues }, .{ "m_b__o_k", genMbOk },
});

fn genSndFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20000"); }
fn genSndAlias(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x10000"); }
fn genSndLoop(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0008"); }
fn genSndMem(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0004"); }
fn genSndPurge(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0040"); }
fn genSndAsync(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0001"); }
fn genSndNoDef(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0002"); }
fn genSndNoStop(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0010"); }
fn genSndNoWait(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x2000"); }
fn genMbAst(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x40"); }
fn genMbExc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x30"); }
fn genMbHand(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x10"); }
fn genMbQues(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x20"); }
fn genMbOk(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "0x0"); }
