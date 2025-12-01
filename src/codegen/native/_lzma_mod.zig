/// Python _lzma module - Internal LZMA support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "l_z_m_a_compressor", genLZMACompressor },
    .{ "l_z_m_a_decompressor", genLZMADecompressor },
    .{ "compress", genCompress },
    .{ "flush", genFlush },
    .{ "decompress", genDecompress },
    .{ "is_check_supported", genIsCheckSupported },
    .{ "encode_filter_properties", genEncodeFilterProperties },
    .{ "decode_filter_properties", genDecodeFilterProperties },
    .{ "f_o_r_m_a_t__a_u_t_o", genFORMAT_AUTO },
    .{ "f_o_r_m_a_t__x_z", genFORMAT_XZ },
    .{ "f_o_r_m_a_t__a_l_o_n_e", genFORMAT_ALONE },
    .{ "f_o_r_m_a_t__r_a_w", genFORMAT_RAW },
    .{ "c_h_e_c_k__n_o_n_e", genCHECK_NONE },
    .{ "c_h_e_c_k__c_r_c32", genCHECK_CRC32 },
    .{ "c_h_e_c_k__c_r_c64", genCHECK_CRC64 },
    .{ "c_h_e_c_k__s_h_a256", genCHECK_SHA256 },
    .{ "p_r_e_s_e_t__d_e_f_a_u_l_t", genPRESET_DEFAULT },
    .{ "p_r_e_s_e_t__e_x_t_r_e_m_e", genPRESET_EXTREME },
    .{ "f_i_l_t_e_r__l_z_m_a1", genFILTER_LZMA1 },
    .{ "f_i_l_t_e_r__l_z_m_a2", genFILTER_LZMA2 },
    .{ "f_i_l_t_e_r__d_e_l_t_a", genFILTER_DELTA },
    .{ "f_i_l_t_e_r__x86", genFILTER_X86 },
    .{ "l_z_m_a_error", genLZMAError },
});

/// Generate _lzma.LZMACompressor(format=FORMAT_XZ, check=-1, preset=None, filters=None)
pub fn genLZMACompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .format = 1, .check = 0 }");
}

/// Generate _lzma.LZMADecompressor(format=FORMAT_AUTO, memlimit=None, filters=None)
pub fn genLZMADecompressor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .format = 0, .eof = false, .needs_input = true, .unused_data = \"\" }");
}

/// Generate LZMACompressor.compress(data)
pub fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate LZMACompressor.flush()
pub fn genFlush(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate LZMADecompressor.decompress(data, max_length=-1)
pub fn genDecompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _lzma.is_check_supported(check_id)
pub fn genIsCheckSupported(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _lzma._encode_filter_properties(filter)
pub fn genEncodeFilterProperties(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _lzma._decode_filter_properties(filter_id, encoded_props)
pub fn genDecodeFilterProperties(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate _lzma.FORMAT_AUTO constant
pub fn genFORMAT_AUTO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _lzma.FORMAT_XZ constant
pub fn genFORMAT_XZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _lzma.FORMAT_ALONE constant
pub fn genFORMAT_ALONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _lzma.FORMAT_RAW constant
pub fn genFORMAT_RAW(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

/// Generate _lzma.CHECK_NONE constant
pub fn genCHECK_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _lzma.CHECK_CRC32 constant
pub fn genCHECK_CRC32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _lzma.CHECK_CRC64 constant
pub fn genCHECK_CRC64(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

/// Generate _lzma.CHECK_SHA256 constant
pub fn genCHECK_SHA256(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 10)");
}

/// Generate _lzma.PRESET_DEFAULT constant
pub fn genPRESET_DEFAULT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

/// Generate _lzma.PRESET_EXTREME constant
pub fn genPRESET_EXTREME(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 0x80000000)");
}

/// Generate _lzma.FILTER_LZMA1 constant
pub fn genFILTER_LZMA1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x4000000000000001)");
}

/// Generate _lzma.FILTER_LZMA2 constant
pub fn genFILTER_LZMA2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x21)");
}

/// Generate _lzma.FILTER_DELTA constant
pub fn genFILTER_DELTA(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x03)");
}

/// Generate _lzma.FILTER_X86 constant
pub fn genFILTER_X86(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x04)");
}

/// Generate _lzma.LZMAError exception
pub fn genLZMAError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.LZMAError");
}
