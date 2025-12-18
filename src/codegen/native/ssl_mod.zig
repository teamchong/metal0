/// Python ssl module - TLS/SSL wrapper for socket objects
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SSLContext", genSSLContext },
    .{ "create_default_context", genCreateDefaultContext },
    .{ "wrap_socket", genWrapSocket },
    .{ "get_default_verify_paths", genGetDefaultVerifyPaths },
    .{ "cert_time_to_seconds", genCertTimeToSeconds },
    .{ "get_server_certificate", genGetServerCertificate },
    .{ "DER_cert_to_PEM_cert", genDERCertToPEMCert },
    .{ "PEM_cert_to_DER_cert", genPEMCertToDERCert },
    .{ "match_hostname", genMatchHostname },
    .{ "RAND_status", genRANDStatus },
    .{ "RAND_add", genRANDAdd },
    .{ "RAND_bytes", genRANDBytes },
    .{ "RAND_pseudo_bytes", genRANDPseudoBytes },
    .{ "PROTOCOL_SSLv23", genProtocolSSLv23 },
    .{ "PROTOCOL_TLS", genProtocolTLS },
    .{ "PROTOCOL_TLS_CLIENT", genProtocolTLSClient },
    .{ "PROTOCOL_TLS_SERVER", genProtocolTLSServer },
    .{ "CERT_NONE", genCertNone },
    .{ "CERT_OPTIONAL", genCertOptional },
    .{ "CERT_REQUIRED", genCertRequired },
    .{ "OP_ALL", genOpAll },
    .{ "OP_NO_SSLv2", genOpNoSSLv2 },
    .{ "OP_NO_SSLv3", genOpNoSSLv3 },
    .{ "OP_NO_TLSv1", genOpNoTLSv1 },
    .{ "OP_NO_TLSv1_1", genOpNoTLSv1_1 },
    .{ "OP_NO_TLSv1_2", genOpNoTLSv1_2 },
    .{ "OP_NO_TLSv1_3", genOpNoTLSv1_3 },
    .{ "HAS_SNI", genHasSNI },
    .{ "HAS_ECDH", genHasECDH },
    .{ "HAS_NPN", genHasNPN },
    .{ "HAS_ALPN", genHasALPN },
    .{ "HAS_TLSv1_3", genHasTLSv1_3 },
    .{ "SSLError", genSSLError },
    .{ "SSLZeroReturnError", genSSLZeroReturnError },
    .{ "SSLWantReadError", genSSLWantReadError },
    .{ "SSLWantWriteError", genSSLWantWriteError },
    .{ "SSLSyscallError", genSSLSyscallError },
    .{ "SSLEOFError", genSSLEOFError },
    .{ "OPENSSL_VERSION", genOpenSSLVersion },
    .{ "OPENSSL_VERSION_INFO", genOpenSSLVersionInfo },
    .{ "OPENSSL_VERSION_NUMBER", genOpenSSLVersionNumber },
});

fn genSSLContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }"), builder_mod.EmitConfig.forExpression());
}

fn genCreateDefaultContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }"), builder_mod.EmitConfig.forExpression());
}

fn genWrapSocket(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetDefaultVerifyPaths(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genCertTimeToSeconds(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetServerCertificate(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genDERCertToPEMCert(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genPEMCertToDERCert(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genMatchHostname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRANDStatus(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genRANDAdd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRANDBytes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genRANDPseudoBytes(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .bytes = \"\", .is_cryptographic = true }"), builder_mod.EmitConfig.forExpression());
}

fn genProtocolSSLv23(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTLS(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTLSClient(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genProtocolTLSServer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
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

fn genOpAll(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x80000BFF), builder_mod.EmitConfig.forExpression());
}

fn genOpNoSSLv2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x01000000), builder_mod.EmitConfig.forExpression());
}

fn genOpNoSSLv3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x02000000), builder_mod.EmitConfig.forExpression());
}

fn genOpNoTLSv1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x04000000), builder_mod.EmitConfig.forExpression());
}

fn genOpNoTLSv1_1(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x10000000), builder_mod.EmitConfig.forExpression());
}

fn genOpNoTLSv1_2(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x08000000), builder_mod.EmitConfig.forExpression());
}

fn genOpNoTLSv1_3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x20000000), builder_mod.EmitConfig.forExpression());
}

fn genHasSNI(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasECDH(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasNPN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genHasALPN(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genHasTLSv1_3(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genSSLError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLError"), builder_mod.EmitConfig.forExpression());
}

fn genSSLZeroReturnError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLZeroReturnError"), builder_mod.EmitConfig.forExpression());
}

fn genSSLWantReadError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLWantReadError"), builder_mod.EmitConfig.forExpression());
}

fn genSSLWantWriteError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLWantWriteError"), builder_mod.EmitConfig.forExpression());
}

fn genSSLSyscallError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLSyscallError"), builder_mod.EmitConfig.forExpression());
}

fn genSSLEOFError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.SSLEOFError"), builder_mod.EmitConfig.forExpression());
}

fn genOpenSSLVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x30000000), builder_mod.EmitConfig.forExpression());
}

fn genOpenSSLVersionInfo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genOpenSSLVersionNumber(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x30000000), builder_mod.EmitConfig.forExpression());
}
