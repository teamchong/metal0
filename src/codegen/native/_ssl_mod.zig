/// Python _ssl module - Internal SSL support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "s_s_l_context", genSslContext },
    .{ "s_s_l_socket", genSslSocket },
    .{ "memory_b_i_o", genMemoryBio },
    .{ "r_a_n_d_status", genRandStatus },
    .{ "r_a_n_d_add", genRandAdd },
    .{ "r_a_n_d_bytes", genRandBytes },
    .{ "r_a_n_d_pseudo_bytes", genRandPseudoBytes },
    .{ "txt2obj", genTxt2Obj },
    .{ "nid2obj", genNid2Obj },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n", genOpensslVersion },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__n_u_m_b_e_r", genOpensslVersionNumber },
    .{ "o_p_e_n_s_s_l__v_e_r_s_i_o_n__i_n_f_o", genOpensslVersionInfo },
    .{ "p_r_o_t_o_c_o_l__s_s_lv23", genProtocolSslv23 },
    .{ "p_r_o_t_o_c_o_l__t_l_s", genProtocolTls },
    .{ "p_r_o_t_o_c_o_l__t_l_s__c_l_i_e_n_t", genProtocolTlsClient },
    .{ "p_r_o_t_o_c_o_l__t_l_s__s_e_r_v_e_r", genProtocolTlsServer },
    .{ "c_e_r_t__n_o_n_e", genCertNone },
    .{ "c_e_r_t__o_p_t_i_o_n_a_l", genCertOptional },
    .{ "c_e_r_t__r_e_q_u_i_r_e_d", genCertRequired },
    .{ "h_a_s__s_n_i", genHasSni },
    .{ "h_a_s__e_c_d_h", genHasEcdh },
    .{ "h_a_s__n_p_n", genHasNpn },
    .{ "h_a_s__a_l_p_n", genHasAlpn },
    .{ "h_a_s__t_l_sv1", genHasTlsv1 },
    .{ "h_a_s__t_l_sv1_1", genHasTlsv11 },
    .{ "h_a_s__t_l_sv1_2", genHasTlsv12 },
    .{ "h_a_s__t_l_sv1_3", genHasTlsv13 },
    .{ "s_s_l_error", genSslError },
    .{ "s_s_l_zero_return_error", genSslZeroReturnError },
    .{ "s_s_l_want_read_error", genSslWantReadError },
    .{ "s_s_l_want_write_error", genSslWantWriteError },
    .{ "s_s_l_syscall_error", genSslSyscallError },
    .{ "s_s_l_e_o_f_error", genSslEofError },
    .{ "s_s_l_cert_verification_error", genSslCertVerificationError },
});

fn genSslContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .protocol = 2, .verify_mode = 0, .check_hostname = false }"), builder_mod.EmitConfig.forExpression());
}

fn genSslSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .context = null, .server_side = false, .server_hostname = null }"), builder_mod.EmitConfig.forExpression());
}

fn genMemoryBio(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .pending = 0, .eof = false }"), builder_mod.EmitConfig.forExpression());
}

fn genRandStatus(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genRandAdd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRandBytes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genRandPseudoBytes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", true }"), builder_mod.EmitConfig.forExpression());
}

fn genTxt2Obj(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genNid2Obj(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("OpenSSL 3.0.0 0 Jan 2024"), builder_mod.EmitConfig.forExpression());
}

fn genOpensslVersionNumber(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x30000000), builder_mod.EmitConfig.forExpression());
}

fn genOpensslVersionInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genProtocolSslv23(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTls(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTlsClient(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTlsServer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(17), builder_mod.EmitConfig.forExpression());
}

fn genCertNone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCertOptional(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genCertRequired(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genHasSni(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasEcdh(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasNpn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genHasAlpn(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasTlsv1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasTlsv11(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasTlsv12(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasTlsv13(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genSslError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLError"), builder_mod.EmitConfig.forExpression());
}

fn genSslZeroReturnError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLZeroReturnError"), builder_mod.EmitConfig.forExpression());
}

fn genSslWantReadError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLWantReadError"), builder_mod.EmitConfig.forExpression());
}

fn genSslWantWriteError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLWantWriteError"), builder_mod.EmitConfig.forExpression());
}

fn genSslSyscallError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLSyscallError"), builder_mod.EmitConfig.forExpression());
}

fn genSslEofError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLEOFError"), builder_mod.EmitConfig.forExpression());
}

fn genSslCertVerificationError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLCertVerificationError"), builder_mod.EmitConfig.forExpression());
}

