/// Python _symtable module - Internal symtable support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "symtable", genSymtable },
    .{ "s_c_o_p_e__o_f_f", genI32(11) }, .{ "s_c_o_p_e__m_a_s_k", genScopeMask },
    .{ "l_o_c_a_l", genI32(1) }, .{ "g_l_o_b_a_l__e_x_p_l_i_c_i_t", genI32(2) }, .{ "g_l_o_b_a_l__i_m_p_l_i_c_i_t", genI32(3) },
    .{ "f_r_e_e", genI32(4) }, .{ "c_e_l_l", genI32(5) },
    .{ "t_y_p_e__f_u_n_c_t_i_o_n", genI32(1) }, .{ "t_y_p_e__c_l_a_s_s", genI32(2) }, .{ "t_y_p_e__m_o_d_u_l_e", genI32(0) },
});

fn genSymtable(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .name = \"top\", .type = \"module\", .id = 0, .lineno = 0 }"); }
fn genScopeMask(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0xf)"); }
