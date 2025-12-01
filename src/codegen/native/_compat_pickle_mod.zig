/// Python _compat_pickle module - Pickle compatibility mappings for Python 2/3
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "n_a_m_e__m_a_p_p_i_n_g", genNAME_MAPPING },
    .{ "i_m_p_o_r_t__m_a_p_p_i_n_g", genIMPORT_MAPPING },
    .{ "r_e_v_e_r_s_e__n_a_m_e__m_a_p_p_i_n_g", genREVERSE_NAME_MAPPING },
    .{ "r_e_v_e_r_s_e__i_m_p_o_r_t__m_a_p_p_i_n_g", genREVERSE_IMPORT_MAPPING },
});

/// Generate _compat_pickle.NAME_MAPPING dict
pub fn genNAME_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.IMPORT_MAPPING dict
pub fn genIMPORT_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.REVERSE_NAME_MAPPING dict
pub fn genREVERSE_NAME_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _compat_pickle.REVERSE_IMPORT_MAPPING dict
pub fn genREVERSE_IMPORT_MAPPING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
