/// Python _ast module - Internal AST support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "py_c_f__o_n_l_y__a_s_t", genPyCF_ONLY_AST },
    .{ "py_c_f__t_y_p_e__c_o_m_m_e_n_t_s", genPyCF_TYPE_COMMENTS },
    .{ "py_c_f__a_l_l_o_w__t_o_p__l_e_v_e_l__a_w_a_i_t", genPyCF_ALLOW_TOP_LEVEL_AWAIT },
});

/// Generate _ast.PyCF_ONLY_AST constant
pub fn genPyCF_ONLY_AST(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x0400)");
}

/// Generate _ast.PyCF_TYPE_COMMENTS constant
pub fn genPyCF_TYPE_COMMENTS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x1000)");
}

/// Generate _ast.PyCF_ALLOW_TOP_LEVEL_AWAIT constant
pub fn genPyCF_ALLOW_TOP_LEVEL_AWAIT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0x2000)");
}
