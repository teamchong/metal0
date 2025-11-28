/// Python _ssl module - Internal SSL support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _ssl._SSLContext(protocol)
pub fn genSSLContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .protocol = 2, .verify_mode = 0, .check_hostname = false }");
}

/// Generate _ssl._SSLSocket(context, sock, server_side, server_hostname, owner, session)
pub fn genSSLSocket(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .context = null, .server_side = false, .server_hostname = null }");
}

/// Generate _ssl.MemoryBIO()
pub fn genMemoryBIO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .pending = 0, .eof = false }");
}

/// Generate _ssl.RAND_status()
pub fn genRAND_status(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.RAND_add(bytes, entropy)
pub fn genRAND_add(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _ssl.RAND_bytes(n)
pub fn genRAND_bytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate _ssl.RAND_pseudo_bytes(n)
pub fn genRAND_pseudo_bytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", true }");
}

/// Generate _ssl.txt2obj(txt, name=False)
pub fn genTxt2obj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }");
}

/// Generate _ssl.nid2obj(nid)
pub fn genNid2obj(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .nid = 0, .shortname = \"\", .longname = \"\", .oid = \"\" }");
}

/// Generate _ssl.OPENSSL_VERSION constant
pub fn genOPENSSL_VERSION(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"OpenSSL 3.0.0 0 Jan 2024\"");
}

/// Generate _ssl.OPENSSL_VERSION_NUMBER constant
pub fn genOPENSSL_VERSION_NUMBER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0x30000000)");
}

/// Generate _ssl.OPENSSL_VERSION_INFO constant
pub fn genOPENSSL_VERSION_INFO(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }");
}

/// Generate _ssl.PROTOCOL_SSLv23 constant
pub fn genPROTOCOL_SSLv23(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _ssl.PROTOCOL_TLS constant
pub fn genPROTOCOL_TLS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _ssl.PROTOCOL_TLS_CLIENT constant
pub fn genPROTOCOL_TLS_CLIENT(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 16)");
}

/// Generate _ssl.PROTOCOL_TLS_SERVER constant
pub fn genPROTOCOL_TLS_SERVER(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 17)");
}

/// Generate _ssl.CERT_NONE constant
pub fn genCERT_NONE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate _ssl.CERT_OPTIONAL constant
pub fn genCERT_OPTIONAL(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _ssl.CERT_REQUIRED constant
pub fn genCERT_REQUIRED(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

/// Generate _ssl.HAS_SNI constant
pub fn genHAS_SNI(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_ECDH constant
pub fn genHAS_ECDH(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_NPN constant
pub fn genHAS_NPN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _ssl.HAS_ALPN constant
pub fn genHAS_ALPN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_TLSv1 constant
pub fn genHAS_TLSv1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_TLSv1_1 constant
pub fn genHAS_TLSv1_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_TLSv1_2 constant
pub fn genHAS_TLSv1_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.HAS_TLSv1_3 constant
pub fn genHAS_TLSv1_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate _ssl.SSLError exception
pub fn genSSLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLError");
}

/// Generate _ssl.SSLZeroReturnError exception
pub fn genSSLZeroReturnError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLZeroReturnError");
}

/// Generate _ssl.SSLWantReadError exception
pub fn genSSLWantReadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLWantReadError");
}

/// Generate _ssl.SSLWantWriteError exception
pub fn genSSLWantWriteError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLWantWriteError");
}

/// Generate _ssl.SSLSyscallError exception
pub fn genSSLSyscallError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLSyscallError");
}

/// Generate _ssl.SSLEOFError exception
pub fn genSSLEOFError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLEOFError");
}

/// Generate _ssl.SSLCertVerificationError exception
pub fn genSSLCertVerificationError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SSLCertVerificationError");
}
