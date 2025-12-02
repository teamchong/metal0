/// Python _lzma module - Internal LZMA support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "l_z_m_a_compressor", genCompressor }, .{ "l_z_m_a_decompressor", genDecompressor },
    .{ "compress", genEmptyStr }, .{ "flush", genEmptyStr }, .{ "decompress", genEmptyStr },
    .{ "is_check_supported", genTrue }, .{ "encode_filter_properties", genEmptyStr }, .{ "decode_filter_properties", genEmpty },
    .{ "f_o_r_m_a_t__a_u_t_o", genI32_0 }, .{ "f_o_r_m_a_t__x_z", genI32_1 }, .{ "f_o_r_m_a_t__a_l_o_n_e", genI32_2 }, .{ "f_o_r_m_a_t__r_a_w", genI32_3 },
    .{ "c_h_e_c_k__n_o_n_e", genI32_0 }, .{ "c_h_e_c_k__c_r_c32", genI32_1 }, .{ "c_h_e_c_k__c_r_c64", genI32_4 }, .{ "c_h_e_c_k__s_h_a256", genI32_10 },
    .{ "p_r_e_s_e_t__d_e_f_a_u_l_t", genI32_6 }, .{ "p_r_e_s_e_t__e_x_t_r_e_m_e", genPresetExtreme },
    .{ "f_i_l_t_e_r__l_z_m_a1", genFilterLzma1 }, .{ "f_i_l_t_e_r__l_z_m_a2", genFilterLzma2 },
    .{ "f_i_l_t_e_r__d_e_l_t_a", genI64_3 }, .{ "f_i_l_t_e_r__x86", genI64_4 },
    .{ "l_z_m_a_error", genLZMAError },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genCompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .format = 1, .check = 0 }"); }
fn genDecompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .format = 0, .eof = false, .needs_input = true, .unused_data = \"\" }"); }
fn genLZMAError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.LZMAError"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI32_10(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 10)"); }
fn genI64_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x03)"); }
fn genI64_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x04)"); }
fn genPresetExtreme(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 0x80000000)"); }
fn genFilterLzma1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x4000000000000001)"); }
fn genFilterLzma2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x21)"); }
