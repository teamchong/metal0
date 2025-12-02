/// Python ssl module - TLS/SSL wrapper for socket objects
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "SSLContext", h.c(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 0), .check_hostname = false }") }, .{ "create_default_context", h.c(".{ .protocol = @as(i32, 2), .verify_mode = @as(i32, 2), .check_hostname = true }") },
    .{ "wrap_socket", h.c("@as(?*anyopaque, null)") }, .{ "get_default_verify_paths", h.c(".{ .cafile = @as(?[]const u8, null), .capath = @as(?[]const u8, null), .openssl_cafile_env = \"SSL_CERT_FILE\", .openssl_cafile = \"\", .openssl_capath_env = \"SSL_CERT_DIR\", .openssl_capath = \"\" }") },
    .{ "cert_time_to_seconds", h.I32(0) }, .{ "get_server_certificate", h.c("\"\"") },
    .{ "DER_cert_to_PEM_cert", h.c("\"\"") }, .{ "PEM_cert_to_DER_cert", h.c("\"\"") },
    .{ "match_hostname", h.c("{}") }, .{ "RAND_status", h.c("true") }, .{ "RAND_add", h.c("{}") },
    .{ "RAND_bytes", h.c("\"\"") }, .{ "RAND_pseudo_bytes", h.c(".{ .bytes = \"\", .is_cryptographic = true }") },
    .{ "PROTOCOL_SSLv23", h.I32(2) }, .{ "PROTOCOL_TLS", h.I32(2) },
    .{ "PROTOCOL_TLS_CLIENT", h.I32(16) }, .{ "PROTOCOL_TLS_SERVER", h.I32(17) },
    .{ "CERT_NONE", h.I32(0) }, .{ "CERT_OPTIONAL", h.I32(1) }, .{ "CERT_REQUIRED", h.I32(2) },
    .{ "OP_ALL", h.I64(0x80000BFF) }, .{ "OP_NO_SSLv2", h.I64(0x01000000) }, .{ "OP_NO_SSLv3", h.I64(0x02000000) },
    .{ "OP_NO_TLSv1", h.I64(0x04000000) }, .{ "OP_NO_TLSv1_1", h.I64(0x10000000) },
    .{ "OP_NO_TLSv1_2", h.I64(0x08000000) }, .{ "OP_NO_TLSv1_3", h.I64(0x20000000) },
    .{ "HAS_SNI", h.c("true") }, .{ "HAS_ECDH", h.c("true") }, .{ "HAS_NPN", h.c("false") },
    .{ "HAS_ALPN", h.c("true") }, .{ "HAS_TLSv1_3", h.c("true") },
    .{ "SSLError", h.err("SSLError") }, .{ "SSLZeroReturnError", h.err("SSLZeroReturnError") },
    .{ "SSLWantReadError", h.err("SSLWantReadError") }, .{ "SSLWantWriteError", h.err("SSLWantWriteError") },
    .{ "SSLSyscallError", h.err("SSLSyscallError") }, .{ "SSLEOFError", h.err("SSLEOFError") },
    .{ "OPENSSL_VERSION", h.I64(0x30000000) }, .{ "OPENSSL_VERSION_INFO", h.c(".{ @as(i32, 3), @as(i32, 0), @as(i32, 0), @as(i32, 0), @as(i32, 0) }") },
    .{ "OPENSSL_VERSION_NUMBER", h.I64(0x30000000) },
});
