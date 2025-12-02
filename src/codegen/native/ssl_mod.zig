/// Python ssl module - TLS/SSL wrapper for socket objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}
fn genI64(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i64, 0x{x})", .{n})); } }.f;
}
fn genErr(comptime name: []const u8) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error." ++ name); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SSLContext", genSSLContext }, .{ "create_default_context", genDefaultContext },
    .{ "wrap_socket", genNull }, .{ "get_default_verify_paths", genVerifyPaths },
    .{ "cert_time_to_seconds", genI32(0) }, .{ "get_server_certificate", genEmptyStr },
    .{ "DER_cert_to_PEM_cert", genEmptyStr }, .{ "PEM_cert_to_DER_cert", genEmptyStr },
    .{ "match_hostname", genUnit }, .{ "RAND_status", genTrue }, .{ "RAND_add", genUnit },
    .{ "RAND_bytes", genEmptyStr }, .{ "RAND_pseudo_bytes", genRandPseudo },
    .{ "PROTOCOL_SSLv23", genI32(2) }, .{ "PROTOCOL_TLS", genI32(2) },
    .{ "PROTOCOL_TLS_CLIENT", genI32(16) }, .{ "PROTOCOL_TLS_SERVER", genI32(17) },
    .{ "CERT_NONE", genI32(0) }, .{ "CERT_OPTIONAL", genI32(1) }, .{ "CERT_REQUIRED", genI32(2) },
    .{ "OP_ALL", genI64(0x80000BFF) }, .{ "OP_NO_SSLv2", genI64(0x01000000) }, .{ "OP_NO_SSLv3", genI64(0x02000000) },
    .{ "OP_NO_TLSv1", genI64(0x04000000) }, .{ "OP_NO_TLSv1_1", genI64(0x10000000) },
    .{ "OP_NO_TLSv1_2", genI64(0x08000000) }, .{ "OP_NO_TLSv1_3", genI64(0x20000000) },
    .{ "HAS_SNI", genTrue }, .{ "HAS_ECDH", genTrue }, .{ "HAS_NPN", genFalse },
    .{ "HAS_ALPN", genTrue }, .{ "HAS_TLSv1_3", genTrue },
    .{ "SSLError", genErr("SSLError") }, .{ "SSLZeroReturnError", genErr("SSLZeroReturnError") },
    .{ "SSLWantReadError", genErr("SSLWantReadError") }, .{ "SSLWantWriteError", genErr("SSLWantWriteError") },
    .{ "SSLSyscallError", genErr("SSLSyscallError") }, .{ "SSLEOFError", genErr("SSLEOFError") },
    .{ "OPENSSL_VERSION", genI64(0x30000000) }, .{ "OPENSSL_VERSION_INFO", genOpenSSLVerInfo },
    .{ "OPENSSL_VERSION_NUMBER", genI64(0x30000000) },
});

fn genSSLContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }"); }
fn genDefaultContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }"); }
fn genVerifyPaths(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }"); }
fn genRandPseudo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .bytes = \"\", .is_cryptographic = true }"); }
fn genOpenSSLVerInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }"); }
