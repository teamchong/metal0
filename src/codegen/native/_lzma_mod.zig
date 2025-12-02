/// Python _lzma module - Internal LZMA support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "l_z_m_a_compressor", genConst(".{ .format = 1, .check = 0 }") }, .{ "l_z_m_a_decompressor", genConst(".{ .format = 0, .eof = false, .needs_input = true, .unused_data = \"\" }") },
    .{ "compress", genConst("\"\"") }, .{ "flush", genConst("\"\"") }, .{ "decompress", genConst("\"\"") },
    .{ "is_check_supported", genConst("true") }, .{ "encode_filter_properties", genConst("\"\"") }, .{ "decode_filter_properties", genConst(".{}") },
    .{ "f_o_r_m_a_t__a_u_t_o", genConst("@as(i32, 0)") }, .{ "f_o_r_m_a_t__x_z", genConst("@as(i32, 1)") }, .{ "f_o_r_m_a_t__a_l_o_n_e", genConst("@as(i32, 2)") }, .{ "f_o_r_m_a_t__r_a_w", genConst("@as(i32, 3)") },
    .{ "c_h_e_c_k__n_o_n_e", genConst("@as(i32, 0)") }, .{ "c_h_e_c_k__c_r_c32", genConst("@as(i32, 1)") }, .{ "c_h_e_c_k__c_r_c64", genConst("@as(i32, 4)") }, .{ "c_h_e_c_k__s_h_a256", genConst("@as(i32, 10)") },
    .{ "p_r_e_s_e_t__d_e_f_a_u_l_t", genConst("@as(i32, 6)") }, .{ "p_r_e_s_e_t__e_x_t_r_e_m_e", genConst("@as(u32, 0x80000000)") },
    .{ "f_i_l_t_e_r__l_z_m_a1", genConst("@as(i64, 0x4000000000000001)") }, .{ "f_i_l_t_e_r__l_z_m_a2", genConst("@as(i64, 0x21)") },
    .{ "f_i_l_t_e_r__d_e_l_t_a", genConst("@as(i64, 0x03)") }, .{ "f_i_l_t_e_r__x86", genConst("@as(i64, 0x04)") },
    .{ "l_z_m_a_error", genConst("error.LZMAError") },
});
