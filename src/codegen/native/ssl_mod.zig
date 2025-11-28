/// Python ssl module - TLS/SSL wrapper for socket objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate ssl.SSLContext(protocol=None)
pub fn genSSLContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }");
}

/// Generate ssl.create_default_context(purpose=Purpose.SERVER_AUTH, ...)
pub fn genCreate_default_context(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }");
}

/// Generate ssl.wrap_socket(sock, ...)
pub fn genWrap_socket(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate ssl.get_default_verify_paths()
pub fn genGet_default_verify_paths(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }");
}

/// Generate ssl.cert_time_to_seconds(cert_time)
pub fn genCert_time_to_seconds(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate ssl.get_server_certificate(addr, ssl_version=None, ca_certs=None)
pub fn genGet_server_certificate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ssl.DER_cert_to_PEM_cert(der_cert)
pub fn genDER_cert_to_PEM_cert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ssl.PEM_cert_to_DER_cert(pem_cert)
pub fn genPEM_cert_to_DER_cert(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ssl.match_hostname(cert, hostname)
pub fn genMatch_hostname(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ssl.RAND_status() - check OpenSSL PRNG status
pub fn genRAND_status(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate ssl.RAND_add(bytes, entropy)
pub fn genRAND_add(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate ssl.RAND_bytes(num)
pub fn genRAND_bytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate ssl.RAND_pseudo_bytes(num)
pub fn genRAND_pseudo_bytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .bytes = \"\", .is_cryptographic = true }");
}

// ============================================================================
// Protocol version constants
// ============================================================================

pub fn genPROTOCOL_SSLv23(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genPROTOCOL_TLS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genPROTOCOL_TLS_CLIENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

pub fn genPROTOCOL_TLS_SERVER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 17)");
}

// ============================================================================
// Verify mode constants
// ============================================================================

pub fn genCERT_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genCERT_OPTIONAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genCERT_REQUIRED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

// ============================================================================
// Option constants
// ============================================================================

pub fn genOP_ALL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x80000BFF)");
}

pub fn genOP_NO_SSLv2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x01000000)");
}

pub fn genOP_NO_SSLv3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x02000000)");
}

pub fn genOP_NO_TLSv1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x04000000)");
}

pub fn genOP_NO_TLSv1_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x10000000)");
}

pub fn genOP_NO_TLSv1_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x08000000)");
}

pub fn genOP_NO_TLSv1_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x20000000)");
}

// ============================================================================
// Exception classes
// ============================================================================

pub fn genSSLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLError");
}

pub fn genSSLZeroReturnError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLZeroReturnError");
}

pub fn genSSLWantReadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLWantReadError");
}

pub fn genSSLWantWriteError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLWantWriteError");
}

pub fn genSSLSyscallError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLSyscallError");
}

pub fn genSSLEOFError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLEOFError");
}

pub fn genSSLCertVerificationError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLCertVerificationError");
}

// ============================================================================
// Purpose enum
// ============================================================================

pub fn genPurpose_SERVER_AUTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nid = @as(i32, 129), .shortname = \"serverAuth\", .longname = \"TLS Web Server Authentication\", .oid = \"1.3.6.1.5.5.7.3.1\" }");
}

pub fn genPurpose_CLIENT_AUTH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nid = @as(i32, 130), .shortname = \"clientAuth\", .longname = \"TLS Web Client Authentication\", .oid = \"1.3.6.1.5.5.7.3.2\" }");
}

// ============================================================================
// Version info
// ============================================================================

pub fn genOPENSSL_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x30000000)"); // OpenSSL 3.x
}

pub fn genOPENSSL_VERSION_INFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }");
}

pub fn genOPENSSL_VERSION_NUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x30000000)");
}

pub fn genHAS_SNI(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

pub fn genHAS_ALPN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

pub fn genHAS_ECDH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

pub fn genHAS_TLSv1_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}
