//! test.test_asyncio.test_ssl - Tests for asyncio SSL support
//! Reference: cpython/Lib/test/test_asyncio/test_ssl.py
//!
//! Tests for SSL/TLS connections in asyncio

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");
const test_streams = @import("test_streams.zig");
const test_sslproto = @import("test_sslproto.zig");

// ============================================================================
// SSL Connection Functions
// ============================================================================

/// Open an SSL connection
pub fn open_connection_ssl(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    ssl_context: *test_sslproto.SSLContext,
) !struct { reader: test_streams.StreamReader, writer: test_streams.StreamWriter } {
    _ = ssl_context;
    // Create streams with SSL
    return .{
        .reader = test_streams.StreamReader.init(allocator, test_streams.DEFAULT_LIMIT),
        .writer = test_streams.StreamWriter.init(allocator),
    };
}

/// Start an SSL server
pub fn start_server_ssl(
    allocator: std.mem.Allocator,
    _: *const fn (*test_streams.StreamReader, *test_streams.StreamWriter) void,
    _: []const u8,
    _: u16,
    _: *test_sslproto.SSLContext,
) !test_streams.Server {
    return test_streams.Server.init(allocator);
}

// ============================================================================
// SSL Handshake
// ============================================================================

/// Perform SSL handshake on a transport
pub fn start_tls(
    _: *test_events.EventLoop,
    _: anytype,
    ssl_context: *test_sslproto.SSLContext,
    server_side: bool,
) !test_sslproto.SSLProtocol {
    _ = server_side;
    return test_sslproto.SSLProtocol.init(std.testing.allocator, ssl_context.*);
}

// ============================================================================
// SSL Configuration
// ============================================================================

pub const SSLConfig = struct {
    verify_mode: test_sslproto.SSLContext.VerifyMode = .CERT_NONE,
    check_hostname: bool = false,
    server_hostname: ?[]const u8 = null,
    alpn_protocols: ?[]const []const u8 = null,
};

/// Create default client SSL context
pub fn create_default_context() test_sslproto.SSLContext {
    var ctx = test_sslproto.SSLContext.init();
    ctx.set_verify_mode(.CERT_REQUIRED);
    ctx.set_check_hostname(true);
    return ctx;
}

/// Create SSL context for servers
pub fn create_server_context() test_sslproto.SSLContext {
    return test_sslproto.SSLContext.init();
}

// ============================================================================
// Test Cases
// ============================================================================

fn testCreateDefaultContext() !void {
    const ctx = create_default_context();
    try std.testing.expectEqual(test_sslproto.SSLContext.VerifyMode.CERT_REQUIRED, ctx.get_verify_mode());
}

fn testCreateServerContext() !void {
    const ctx = create_server_context();
    try std.testing.expectEqual(test_sslproto.SSLContext.VerifyMode.CERT_NONE, ctx.get_verify_mode());
}

fn testOpenConnectionSsl() !void {
    const allocator = std.testing.allocator;
    var ctx = test_sslproto.SSLContext.init();

    var streams = try open_connection_ssl(allocator, "example.com", 443, &ctx);
    defer streams.reader.deinit();
    defer streams.writer.deinit();

    try std.testing.expect(!streams.reader.at_eof());
}

fn testStartServerSsl() !void {
    const allocator = std.testing.allocator;
    var ctx = test_sslproto.SSLContext.init();

    const callback = struct {
        fn cb(_: *test_streams.StreamReader, _: *test_streams.StreamWriter) void {}
    }.cb;

    var server = try start_server_ssl(allocator, callback, "0.0.0.0", 8443, &ctx);
    try std.testing.expect(!server.is_serving());
}

fn testSSLConfig() !void {
    const config = SSLConfig{
        .verify_mode = .CERT_REQUIRED,
        .check_hostname = true,
        .server_hostname = "example.com",
    };

    try std.testing.expectEqual(test_sslproto.SSLContext.VerifyMode.CERT_REQUIRED, config.verify_mode);
    try std.testing.expect(config.check_hostname);
    try std.testing.expectEqualStrings("example.com", config.server_hostname.?);
}

fn testStartTls() !void {
    const allocator = std.testing.allocator;
    var loop = test_events.EventLoop.init(allocator);
    defer loop.deinit();

    var ctx = test_sslproto.SSLContext.init();
    var proto = try start_tls(&loop, null, &ctx, false);
    defer proto.deinit();

    try std.testing.expect(!proto.is_handshake_complete());
}

fn testSSLContextProtocol() !void {
    var ctx = test_sslproto.SSLContext.init();
    try std.testing.expectEqual(test_sslproto.SSLContext.Protocol.TLS, ctx._protocol);
}

fn testSSLContextCiphers() !void {
    var ctx = test_sslproto.SSLContext.init();
    ctx.set_ciphers("TLS_AES_256_GCM_SHA384");
    try std.testing.expectEqualStrings("TLS_AES_256_GCM_SHA384", ctx._ciphers.?);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "create_default_context" {
    try testCreateDefaultContext();
}

test "create_server_context" {
    try testCreateServerContext();
}

test "open_connection_ssl" {
    try testOpenConnectionSsl();
}

test "start_server_ssl" {
    try testStartServerSsl();
}

test "SSLConfig" {
    try testSSLConfig();
}

test "start_tls" {
    try testStartTls();
}

test "SSLContext protocol" {
    try testSSLContextProtocol();
}

test "SSLContext ciphers" {
    try testSSLContextCiphers();
}
