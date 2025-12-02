/// Python ssl module - TLS/SSL wrapper for socket objects
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "SSLContext", genConst(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }") }, .{ "create_default_context", genConst(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }") },
    .{ "wrap_socket", genConst("@as(?*anyopaque, null)") }, .{ "get_default_verify_paths", genConst(".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }") },
    .{ "cert_time_to_seconds", genConst("@as(i32, 0)") }, .{ "get_server_certificate", genConst("\"\"") },
    .{ "DER_cert_to_PEM_cert", genConst("\"\"") }, .{ "PEM_cert_to_DER_cert", genConst("\"\"") },
    .{ "match_hostname", genConst("{}") }, .{ "RAND_status", genConst("true") }, .{ "RAND_add", genConst("{}") },
    .{ "RAND_bytes", genConst("\"\"") }, .{ "RAND_pseudo_bytes", genConst(".{ .bytes = \"\", .is_cryptographic = true }") },
    .{ "PROTOCOL_SSLv23", genConst("@as(i32, 2)") }, .{ "PROTOCOL_TLS", genConst("@as(i32, 2)") },
    .{ "PROTOCOL_TLS_CLIENT", genConst("@as(i32, 16)") }, .{ "PROTOCOL_TLS_SERVER", genConst("@as(i32, 17)") },
    .{ "CERT_NONE", genConst("@as(i32, 0)") }, .{ "CERT_OPTIONAL", genConst("@as(i32, 1)") }, .{ "CERT_REQUIRED", genConst("@as(i32, 2)") },
    .{ "OP_ALL", genConst("@as(i64, 0x80000BFF)") }, .{ "OP_NO_SSLv2", genConst("@as(i64, 0x01000000)") }, .{ "OP_NO_SSLv3", genConst("@as(i64, 0x02000000)") },
    .{ "OP_NO_TLSv1", genConst("@as(i64, 0x04000000)") }, .{ "OP_NO_TLSv1_1", genConst("@as(i64, 0x10000000)") },
    .{ "OP_NO_TLSv1_2", genConst("@as(i64, 0x08000000)") }, .{ "OP_NO_TLSv1_3", genConst("@as(i64, 0x20000000)") },
    .{ "HAS_SNI", genConst("true") }, .{ "HAS_ECDH", genConst("true") }, .{ "HAS_NPN", genConst("false") },
    .{ "HAS_ALPN", genConst("true") }, .{ "HAS_TLSv1_3", genConst("true") },
    .{ "SSLError", genConst("error.SSLError") }, .{ "SSLZeroReturnError", genConst("error.SSLZeroReturnError") },
    .{ "SSLWantReadError", genConst("error.SSLWantReadError") }, .{ "SSLWantWriteError", genConst("error.SSLWantWriteError") },
    .{ "SSLSyscallError", genConst("error.SSLSyscallError") }, .{ "SSLEOFError", genConst("error.SSLEOFError") },
    .{ "OPENSSL_VERSION", genConst("@as(i64, 0x30000000)") }, .{ "OPENSSL_VERSION_INFO", genConst(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "OPENSSL_VERSION_NUMBER", genConst("@as(i64, 0x30000000)") },
});
