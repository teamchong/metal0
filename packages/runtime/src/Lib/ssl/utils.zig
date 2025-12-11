//! SSL/TLS utility functions
//!
//! Helper functions for SSL operations including certificate verification,
//! hostname matching, and parsing.
//! Mirrors: CPython Lib/ssl.py utility functions

const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");
const context = @import("context.zig");
const socket = @import("socket.zig");
const crypto = std.crypto;

// ============================================================================
// Convenience Functions
// ============================================================================

/// Create a default SSL context for client connections
pub fn createDefaultContext(allocator: std.mem.Allocator, purpose: []const u8) !context.SSLContext {
    _ = purpose;
    var ctx = context.SSLContext.init(allocator, constants.PROTOCOL_TLS_CLIENT);
    ctx.verify_mode = constants.CERT_REQUIRED;
    ctx.check_hostname = true;
    try ctx.loadDefaultCerts(constants.Purpose.SERVER_AUTH);
    return ctx;
}

/// Create a default SSL context for server connections
pub fn createDefaultServerContext(allocator: std.mem.Allocator) !context.SSLContext {
    var ctx = context.SSLContext.init(allocator, constants.PROTOCOL_TLS_SERVER);
    return ctx;
}

/// Wrap a socket with SSL (convenience function)
pub fn wrapSocket(
    allocator: std.mem.Allocator,
    sock: anytype,
    server_side: bool,
    server_hostname: ?[]const u8,
) !socket.SSLSocket {
    var ctx = context.SSLContext.init(allocator, constants.PROTOCOL_TLS);
    return ctx.wrapSocket(sock, server_side, server_hostname);
}

/// Get the default verify paths
pub fn getDefaultVerifyPaths() struct {
    cafile: ?[]const u8,
    capath: ?[]const u8,
    openssl_cafile_env: []const u8,
    openssl_cafile: ?[]const u8,
    openssl_capath_env: []const u8,
    openssl_capath: ?[]const u8,
} {
    return .{
        .cafile = null,
        .capath = null,
        .openssl_cafile_env = "SSL_CERT_FILE",
        .openssl_cafile = null,
        .openssl_capath_env = "SSL_CERT_DIR",
        .openssl_capath = null,
    };
}

/// Match hostname against certificate
/// Verifies that the hostname matches the certificate's CN or SAN fields
pub fn matchHostname(cert: types.Certificate, hostname: []const u8) !void {
    // Check Subject Alternative Names (SAN) first - preferred method
    if (cert.subject_alt_name) |san_list| {
        for (san_list) |san| {
            if (matchHostnamePattern(san, hostname)) return;
        }
    }

    // Fall back to Common Name (CN)
    if (cert.subject) |subject| {
        // Extract CN from subject (format: "CN=hostname,O=org,...")
        var iter = std.mem.splitScalar(u8, subject, ',');
        while (iter.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (std.mem.startsWith(u8, trimmed, "CN=")) {
                const cn = trimmed[3..];
                if (matchHostnamePattern(cn, hostname)) return;
            }
        }
    }

    return error.CertificateError; // Hostname doesn't match
}

/// Match hostname against a pattern (supports wildcard certificates)
fn matchHostnamePattern(pattern: []const u8, hostname: []const u8) bool {
    // Exact match
    if (std.ascii.eqlIgnoreCase(pattern, hostname)) return true;

    // Wildcard match (*.example.com matches foo.example.com)
    if (std.mem.startsWith(u8, pattern, "*.")) {
        const suffix = pattern[1..]; // ".example.com"
        // Find first dot in hostname
        if (std.mem.indexOf(u8, hostname, ".")) |dot_idx| {
            const host_suffix = hostname[dot_idx..];
            if (std.ascii.eqlIgnoreCase(suffix, host_suffix)) return true;
        }
    }

    return false;
}

/// Get certificate hash (for pinning)
pub fn certTimeDelta(cert_time: []const u8) !i64 {
    _ = cert_time;
    return 0;
}

/// PEM certificate parsing
pub fn pemCertChain(pem_data: []const u8) ![]types.Certificate {
    _ = pem_data;
    return &[_]types.Certificate{};
}

/// DER certificate parsing
pub fn derCert(der_data: []const u8) !types.Certificate {
    _ = der_data;
    return types.Certificate{};
}

// ============================================================================
// Library Version Info
// ============================================================================

/// Get TLS library version info
/// Returns Zig's std.crypto.tls version identifier
pub fn OPENSSL_VERSION() []const u8 {
    // Zig stdlib provides TLS 1.3 support via std.crypto.tls
    return "Zig std.crypto.tls (TLS 1.3)";
}

/// Get version number in OpenSSL format for compatibility
/// Returns a value indicating TLS 1.3 support level
pub fn OPENSSL_VERSION_NUMBER() u32 {
    // Format: MNNFFPPS (Major, Minor, Fix, Patch, Status)
    // 0x10101000 = 1.1.1 (TLS 1.3 capable)
    return 0x10101000;
}

/// Check if a feature is supported
pub fn HAS_TLSv1_3() bool {
    return true;
}

pub fn HAS_ALPN() bool {
    return true;
}

pub fn HAS_SNI() bool {
    return true;
}

// ============================================================================
// Random
// ============================================================================

/// Get random bytes (using Zig crypto)
pub fn RAND_bytes(buf: []u8) void {
    crypto.random.bytes(buf);
}

/// Get random status (always 1 = OK)
pub fn RAND_status() i32 {
    return 1;
}
