/// Python _lzma module - Internal LZMA support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "l_z_m_a_compressor", genLzmaCompressor },
    .{ "l_z_m_a_decompressor", genLzmaDecompressor },
    .{ "compress", genCompress },
    .{ "flush", genFlush },
    .{ "decompress", genDecompress },
    .{ "is_check_supported", genIsCheckSupported },
    .{ "encode_filter_properties", genEncodeFilterProperties },
    .{ "decode_filter_properties", genDecodeFilterProperties },
    .{ "f_o_r_m_a_t__a_u_t_o", genFormatAuto },
    .{ "f_o_r_m_a_t__x_z", genFormatXz },
    .{ "f_o_r_m_a_t__a_l_o_n_e", genFormatAlone },
    .{ "f_o_r_m_a_t__r_a_w", genFormatRaw },
    .{ "c_h_e_c_k__n_o_n_e", genCheckNone },
    .{ "c_h_e_c_k__c_r_c32", genCheckCrc32 },
    .{ "c_h_e_c_k__c_r_c64", genCheckCrc64 },
    .{ "c_h_e_c_k__s_h_a256", genCheckSha256 },
    .{ "p_r_e_s_e_t__d_e_f_a_u_l_t", genPresetDefault },
    .{ "p_r_e_s_e_t__e_x_t_r_e_m_e", genPresetExtreme },
    .{ "f_i_l_t_e_r__l_z_m_a1", genFilterLzma1 },
    .{ "f_i_l_t_e_r__l_z_m_a2", genFilterLzma2 },
    .{ "f_i_l_t_e_r__d_e_l_t_a", genFilterDelta },
    .{ "f_i_l_t_e_r__x86", genFilterX86 },
    .{ "l_z_m_a_error", genLzmaError },
});

fn genLzmaCompressor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .format = 1, .check = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genLzmaDecompressor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .format = 0, .eof = false, .needs_input = true, .unused_data = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genCompress(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genFlush(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genDecompress(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genIsCheckSupported(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genEncodeFilterProperties(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genDecodeFilterProperties(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genFormatAuto(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genFormatXz(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genFormatAlone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genFormatRaw(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genCheckNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCheckCrc32(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genCheckCrc64(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genCheckSha256(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(10), builder_mod.EmitConfig.forExpression());
}

fn genPresetDefault(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(6), builder_mod.EmitConfig.forExpression());
}

fn genPresetExtreme(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0x80000000)"), builder_mod.EmitConfig.forExpression());
}

fn genFilterLzma1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x4000000000000001)"), builder_mod.EmitConfig.forExpression());
}

fn genFilterLzma2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x21), builder_mod.EmitConfig.forExpression());
}

fn genFilterDelta(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x03), builder_mod.EmitConfig.forExpression());
}

fn genFilterX86(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x04), builder_mod.EmitConfig.forExpression());
}

fn genLzmaError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.LZMAError"), builder_mod.EmitConfig.forExpression());
}

