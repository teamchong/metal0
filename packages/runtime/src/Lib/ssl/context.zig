//! SSL context for configuration
//!
//! Provides SSLContext for configuring SSL/TLS connections.
//! Mirrors: CPython Lib/ssl.py SSLContext

const std = @import("std");
const constants = @import("constants.zig");
const types = @import("types.zig");

/// An SSL context for configuring SSL connections
pub const SSLContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    protocol: i32,
    verify_mode: i32,
    check_hostname: bool,
    options: u32,
    ca_certs: ?[]const u8,
    certfile: ?[]const u8,
    keyfile: ?[]const u8,
    ciphers: ?[]const u8,
    alpn_protocols: ?[]const []const u8,
    hostname_checks_common_name: bool,
    minimum_version: TLSVersion,
    maximum_version: TLSVersion,

    pub const TLSVersion = enum {
        TLSv1,
        TLSv1_1,
        TLSv1_2,
        TLSv1_3,
        MINIMUM_SUPPORTED,
        MAXIMUM_SUPPORTED,
    };

    pub fn init(allocator: std.mem.Allocator, protocol: i32) Self {
        return .{
            .allocator = allocator,
            .protocol = protocol,
            .verify_mode = constants.CERT_NONE,
            .check_hostname = false,
            .options = constants.OP_ALL | constants.OP_NO_SSLv2 | constants.OP_NO_SSLv3,
            .ca_certs = null,
            .certfile = null,
            .keyfile = null,
            .ciphers = null,
            .alpn_protocols = null,
            .hostname_checks_common_name = true,
            .minimum_version = .MINIMUM_SUPPORTED,
            .maximum_version = .MAXIMUM_SUPPORTED,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Load CA certificates
    pub fn loadVerifyLocations(self: *Self, cafile: ?[]const u8, capath: ?[]const u8, cadata: ?[]const u8) !void {
        _ = capath;
        _ = cadata;
        self.ca_certs = cafile;
    }

    /// Load certificate chain file
    pub fn loadCertChain(self: *Self, certfile: []const u8, keyfile: ?[]const u8, password: ?[]const u8) !void {
        _ = password;
        self.certfile = certfile;
        self.keyfile = keyfile;
    }

    /// Load default CA certificates from system locations
    pub fn loadDefaultCerts(self: *Self, purpose: []const u8) !void {
        _ = purpose;

        // Try common system CA certificate locations
        const ca_paths = [_][]const u8{
            "/etc/ssl/certs/ca-certificates.crt", // Debian/Ubuntu
            "/etc/pki/tls/certs/ca-bundle.crt", // RHEL/CentOS
            "/etc/ssl/ca-bundle.pem", // OpenSUSE
            "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem", // Fedora
            "/etc/ssl/cert.pem", // macOS/Alpine
            "/usr/local/share/certs/ca-root-nss.crt", // FreeBSD
        };

        for (ca_paths) |path| {
            if (std.fs.cwd().access(path, .{})) {
                self.ca_certs = path;
                return;
            } else |_| {}
        }

        // On macOS, also check for Keychain (path marker)
        if (comptime @import("builtin").os.tag == .macos) {
            self.ca_certs = "/System/Library/Keychains/SystemRootCertificates.keychain";
        }
    }

    /// Set ciphers
    pub fn setCiphers(self: *Self, ciphers: []const u8) !void {
        self.ciphers = ciphers;
    }

    /// Set ALPN protocols
    pub fn setAlpnProtocols(self: *Self, protocols: []const []const u8) !void {
        self.alpn_protocols = protocols;
    }

    /// Set verification mode
    pub fn setVerifyMode(self: *Self, mode: i32) void {
        self.verify_mode = mode;
        if (mode == constants.CERT_REQUIRED) {
            self.check_hostname = true;
        }
    }

    /// Wrap a socket
    pub fn wrapSocket(
        self: *Self,
        sock: anytype,
        server_side: bool,
        server_hostname: ?[]const u8,
    ) !@import("socket.zig").SSLSocket {
        return @import("socket.zig").SSLSocket.init(self.allocator, self, sock, server_side, server_hostname);
    }

    /// Get CA certs info
    pub fn getCaCerts(self: *Self) ?[]const u8 {
        return self.ca_certs;
    }

    /// Get session statistics
    /// Tracks SSL/TLS session cache statistics
    pub fn sessionStats(self: *Self) types.SessionStats {
        return self.stats;
    }

    /// Increment connect count (called on successful handshake)
    pub fn recordConnect(self: *Self, success: bool) void {
        self.stats.connect += 1;
        if (success) {
            self.stats.connect_good += 1;
        }
    }

    /// Increment accept count (for server mode)
    pub fn recordAccept(self: *Self, success: bool) void {
        self.stats.accept += 1;
        if (success) {
            self.stats.accept_good += 1;
        }
    }

    /// Record session cache hit/miss
    pub fn recordCacheAccess(self: *Self, hit: bool) void {
        if (hit) {
            self.stats.hits += 1;
        } else {
            self.stats.misses += 1;
        }
    }

    /// Statistics tracking
    stats: types.SessionStats = .{},
};
