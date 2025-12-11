//! SSL/TLS data types
//!
//! Certificate and cipher information structures.
//! Mirrors: CPython Lib/ssl.py types

/// Certificate information
pub const Certificate = struct {
    subject: ?[]const u8 = null,
    issuer: ?[]const u8 = null,
    version: i32 = 3,
    serial_number: ?[]const u8 = null,
    not_before: ?[]const u8 = null,
    not_after: ?[]const u8 = null,
    subject_alt_name: ?[]const []const u8 = null,
};

/// Cipher information
pub const CipherInfo = struct {
    name: []const u8,
    protocol: []const u8,
    bits: i32,
};

/// Session statistics
pub const SessionStats = struct {
    number: usize = 0,
    connect: usize = 0,
    connect_good: usize = 0,
    connect_renegotiate: usize = 0,
    accept: usize = 0,
    accept_good: usize = 0,
    accept_renegotiate: usize = 0,
    hits: usize = 0,
    misses: usize = 0,
    timeouts: usize = 0,
    cache_full: usize = 0,
};
