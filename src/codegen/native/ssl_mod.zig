/// Python ssl module - TLS/SSL wrapper for socket objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SSLContext", genSSLContext }, .{ "create_default_context", genDefaultContext },
    .{ "wrap_socket", genNull }, .{ "get_default_verify_paths", genVerifyPaths },
    .{ "cert_time_to_seconds", genI64_0 }, .{ "get_server_certificate", genEmptyStr },
    .{ "DER_cert_to_PEM_cert", genEmptyStr }, .{ "PEM_cert_to_DER_cert", genEmptyStr },
    .{ "match_hostname", genUnit }, .{ "RAND_status", genTrue }, .{ "RAND_add", genUnit },
    .{ "RAND_bytes", genEmptyStr }, .{ "RAND_pseudo_bytes", genRandPseudo },
    .{ "PROTOCOL_SSLv23", genI32_2 }, .{ "PROTOCOL_TLS", genI32_2 },
    .{ "PROTOCOL_TLS_CLIENT", genI32_16 }, .{ "PROTOCOL_TLS_SERVER", genI32_17 },
    .{ "CERT_NONE", genI32_0 }, .{ "CERT_OPTIONAL", genI32_1 }, .{ "CERT_REQUIRED", genI32_2 },
    .{ "OP_ALL", genOP_ALL }, .{ "OP_NO_SSLv2", genOP_NO_SSLv2 }, .{ "OP_NO_SSLv3", genOP_NO_SSLv3 },
    .{ "OP_NO_TLSv1", genOP_NO_TLSv1 }, .{ "OP_NO_TLSv1_1", genOP_NO_TLSv1_1 },
    .{ "OP_NO_TLSv1_2", genOP_NO_TLSv1_2 }, .{ "OP_NO_TLSv1_3", genOP_NO_TLSv1_3 },
    .{ "HAS_SNI", genTrue }, .{ "HAS_ECDH", genTrue }, .{ "HAS_NPN", genFalse },
    .{ "HAS_ALPN", genTrue }, .{ "HAS_TLSv1_3", genTrue },
    .{ "SSLError", genSSLError }, .{ "SSLZeroReturnError", genSSLZeroReturnError },
    .{ "SSLWantReadError", genSSLWantReadError }, .{ "SSLWantWriteError", genSSLWantWriteError },
    .{ "SSLSyscallError", genSSLSyscallError }, .{ "SSLEOFError", genSSLEOFError },
    .{ "OPENSSL_VERSION", genOpenSSLVer }, .{ "OPENSSL_VERSION_INFO", genOpenSSLVerInfo },
    .{ "OPENSSL_VERSION_NUMBER", genOpenSSLVer },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_16(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 16)"); }
fn genI32_17(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 17)"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }

// OP flags
fn genOP_ALL(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x80000BFF)"); }
fn genOP_NO_SSLv2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x01000000)"); }
fn genOP_NO_SSLv3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x02000000)"); }
fn genOP_NO_TLSv1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x04000000)"); }
fn genOP_NO_TLSv1_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x10000000)"); }
fn genOP_NO_TLSv1_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x08000000)"); }
fn genOP_NO_TLSv1_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x20000000)"); }

// SSL Errors
fn genSSLError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLError"); }
fn genSSLZeroReturnError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLZeroReturnError"); }
fn genSSLWantReadError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLWantReadError"); }
fn genSSLWantWriteError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLWantWriteError"); }
fn genSSLSyscallError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLSyscallError"); }
fn genSSLEOFError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SSLEOFError"); }

// OpenSSL version
fn genOpenSSLVer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x30000000)"); }
fn genOpenSSLVerInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }"); }

// Complex types
fn genSSLContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }"); }
fn genDefaultContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }"); }
fn genVerifyPaths(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }"); }
fn genRandPseudo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(".{ .bytes = \"\", .is_cryptographic = true }"); }
