//! CPython source: Lib/ssl.py
//!
//! Provides access to Transport Layer Security encryption and
//! peer authentication facilities.
//!
//! Mirrors: CPython Lib/ssl.py

// Re-export all submodules
pub const constants = @import("ssl/constants.zig");
pub const errors = @import("ssl/errors.zig");
pub const types = @import("ssl/types.zig");
pub const context = @import("ssl/context.zig");
pub const socket = @import("ssl/socket.zig");
pub const utils = @import("ssl/utils.zig");

// Re-export commonly used types and constants
pub const PROTOCOL_TLS = constants.PROTOCOL_TLS;
pub const PROTOCOL_TLS_CLIENT = constants.PROTOCOL_TLS_CLIENT;
pub const PROTOCOL_TLS_SERVER = constants.PROTOCOL_TLS_SERVER;
pub const PROTOCOL_SSLv23 = constants.PROTOCOL_SSLv23;

pub const CERT_NONE = constants.CERT_NONE;
pub const CERT_OPTIONAL = constants.CERT_OPTIONAL;
pub const CERT_REQUIRED = constants.CERT_REQUIRED;

pub const OP_NO_SSLv2 = constants.OP_NO_SSLv2;
pub const OP_NO_SSLv3 = constants.OP_NO_SSLv3;
pub const OP_NO_TLSv1 = constants.OP_NO_TLSv1;
pub const OP_NO_TLSv1_1 = constants.OP_NO_TLSv1_1;
pub const OP_NO_TLSv1_2 = constants.OP_NO_TLSv1_2;
pub const OP_NO_TLSv1_3 = constants.OP_NO_TLSv1_3;
pub const OP_ALL = constants.OP_ALL;

pub const AlertDescription = constants.AlertDescription;
pub const Purpose = constants.Purpose;

pub const SSLContext = context.SSLContext;
pub const SSLSocket = socket.SSLSocket;
pub const Certificate = types.Certificate;
pub const CipherInfo = types.CipherInfo;
pub const SessionStats = types.SessionStats;

pub const SSLError = errors.SSLError;
pub const CertificateError = errors.CertificateError;

pub const createDefaultContext = utils.createDefaultContext;
pub const createDefaultServerContext = utils.createDefaultServerContext;
pub const wrapSocket = utils.wrapSocket;
pub const getDefaultVerifyPaths = utils.getDefaultVerifyPaths;
pub const matchHostname = utils.matchHostname;
pub const certTimeDelta = utils.certTimeDelta;
pub const pemCertChain = utils.pemCertChain;
pub const derCert = utils.derCert;

pub const OPENSSL_VERSION = utils.OPENSSL_VERSION;
pub const OPENSSL_VERSION_NUMBER = utils.OPENSSL_VERSION_NUMBER;
pub const HAS_TLSv1_3 = utils.HAS_TLSv1_3;
pub const HAS_ALPN = utils.HAS_ALPN;
pub const HAS_SNI = utils.HAS_SNI;

pub const RAND_bytes = utils.RAND_bytes;
pub const RAND_status = utils.RAND_status;

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");

test "SSLContext init" {
    const allocator = std.testing.allocator;

    var ctx = SSLContext.init(allocator, PROTOCOL_TLS);
    defer ctx.deinit();

    try std.testing.expectEqual(CERT_NONE, ctx.verify_mode);
    try std.testing.expect(!ctx.check_hostname);
}

test "SSLContext verify mode" {
    const allocator = std.testing.allocator;

    var ctx = SSLContext.init(allocator, PROTOCOL_TLS_CLIENT);
    defer ctx.deinit();

    ctx.setVerifyMode(CERT_REQUIRED);
    try std.testing.expectEqual(CERT_REQUIRED, ctx.verify_mode);
    try std.testing.expect(ctx.check_hostname);
}

test "constants" {
    try std.testing.expectEqual(@as(i32, 0), CERT_NONE);
    try std.testing.expectEqual(@as(i32, 1), CERT_OPTIONAL);
    try std.testing.expectEqual(@as(i32, 2), CERT_REQUIRED);
}

test "version info" {
    try std.testing.expect(HAS_TLSv1_3());
    try std.testing.expect(HAS_ALPN());
    try std.testing.expect(HAS_SNI());
}

test "random" {
    var buf: [16]u8 = undefined;
    RAND_bytes(&buf);
    try std.testing.expectEqual(@as(i32, 1), RAND_status());
}

test "default verify paths" {
    const paths = getDefaultVerifyPaths();
    try std.testing.expectEqualStrings("SSL_CERT_FILE", paths.openssl_cafile_env);
}
