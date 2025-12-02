/// Hashlib - Cryptographic Hash Functions
/// Python-compatible API for hashlib module
/// Uses incremental hashing for O(n) performance instead of O(n²) accumulation
const std = @import("std");

// Use Zig's built-in crypto
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Sha512 = std.crypto.hash.sha2.Sha512;
const Sha384 = std.crypto.hash.sha2.Sha384;
const Sha224 = std.crypto.hash.sha2.Sha224;

pub const Algorithm = enum {
    md5,
    sha1,
    sha224,
    sha256,
    sha384,
    sha512,
};

/// Hasher union - stores the actual incremental hasher state
const HasherState = union(Algorithm) {
    md5: Md5,
    sha1: Sha1,
    sha224: Sha224,
    sha256: Sha256,
    sha384: Sha384,
    sha512: Sha512,
};

/// Generic hash object interface - uses incremental hashing
pub const HashObject = struct {
    state: HasherState,
    digest_size: usize,
    block_size: usize,
    name: []const u8,

    /// Update hash with more data - O(n) incremental!
    pub fn update(self: *HashObject, input: []const u8) void {
        switch (self.state) {
            .md5 => |*h| h.update(input),
            .sha1 => |*h| h.update(input),
            .sha224 => |*h| h.update(input),
            .sha256 => |*h| h.update(input),
            .sha384 => |*h| h.update(input),
            .sha512 => |*h| h.update(input),
        }
    }

    /// Get the digest as bytes (returns a copy that caller must free)
    pub fn digest(self: *HashObject, allocator: std.mem.Allocator) ![]u8 {
        switch (self.state) {
            .md5 => |*h| {
                const result = try allocator.alloc(u8, Md5.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Md5.digest_length]);
                return result;
            },
            .sha1 => |*h| {
                const result = try allocator.alloc(u8, Sha1.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Sha1.digest_length]);
                return result;
            },
            .sha224 => |*h| {
                const result = try allocator.alloc(u8, Sha224.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Sha224.digest_length]);
                return result;
            },
            .sha256 => |*h| {
                const result = try allocator.alloc(u8, Sha256.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Sha256.digest_length]);
                return result;
            },
            .sha384 => |*h| {
                const result = try allocator.alloc(u8, Sha384.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Sha384.digest_length]);
                return result;
            },
            .sha512 => |*h| {
                const result = try allocator.alloc(u8, Sha512.digest_length);
                var hasher = h.*;
                hasher.final(result[0..Sha512.digest_length]);
                return result;
            },
        }
    }

    /// Get the digest as hex string
    pub fn hexdigest(self: *HashObject, allocator: std.mem.Allocator) ![]u8 {
        const d = try self.digest(allocator);
        defer allocator.free(d);
        const hex = try allocator.alloc(u8, d.len * 2);
        const hex_chars = "0123456789abcdef";
        for (d, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        return hex;
    }

    /// Copy the hash object (copies hasher state)
    pub fn copy(self: *const HashObject) HashObject {
        return HashObject{
            .state = self.state,
            .digest_size = self.digest_size,
            .block_size = self.block_size,
            .name = self.name,
        };
    }

    /// Free the hash object resources (no-op for incremental hasher)
    pub fn deinit(self: *HashObject) void {
        _ = self;
    }
};

/// Create MD5 hash object
pub fn md5() HashObject {
    return HashObject{
        .state = .{ .md5 = Md5.init(.{}) },
        .digest_size = Md5.digest_length,
        .block_size = Md5.block_length,
        .name = "md5",
    };
}

/// Create SHA1 hash object
pub fn sha1() HashObject {
    return HashObject{
        .state = .{ .sha1 = Sha1.init(.{}) },
        .digest_size = Sha1.digest_length,
        .block_size = Sha1.block_length,
        .name = "sha1",
    };
}

/// Create SHA224 hash object
pub fn sha224() HashObject {
    return HashObject{
        .state = .{ .sha224 = Sha224.init(.{}) },
        .digest_size = Sha224.digest_length,
        .block_size = Sha224.block_length,
        .name = "sha224",
    };
}

/// Create SHA256 hash object
pub fn sha256() HashObject {
    return HashObject{
        .state = .{ .sha256 = Sha256.init(.{}) },
        .digest_size = Sha256.digest_length,
        .block_size = Sha256.block_length,
        .name = "sha256",
    };
}

/// Create SHA384 hash object
pub fn sha384() HashObject {
    return HashObject{
        .state = .{ .sha384 = Sha384.init(.{}) },
        .digest_size = Sha384.digest_length,
        .block_size = Sha384.block_length,
        .name = "sha384",
    };
}

/// Create SHA512 hash object
pub fn sha512() HashObject {
    return HashObject{
        .state = .{ .sha512 = Sha512.init(.{}) },
        .digest_size = Sha512.digest_length,
        .block_size = Sha512.block_length,
        .name = "sha512",
    };
}

/// Create hash object by name (Python's hashlib.new())
pub fn new(name: []const u8) !HashObject {
    if (std.mem.eql(u8, name, "md5")) return md5();
    if (std.mem.eql(u8, name, "sha1")) return sha1();
    if (std.mem.eql(u8, name, "sha224")) return sha224();
    if (std.mem.eql(u8, name, "sha256")) return sha256();
    if (std.mem.eql(u8, name, "sha384")) return sha384();
    if (std.mem.eql(u8, name, "sha512")) return sha512();
    return error.UnsupportedAlgorithm;
}

// ============================================================================
// Convenience one-shot functions
// ============================================================================

/// One-shot MD5 hash
pub fn md5Hash(data: []const u8, out: *[Md5.digest_length]u8) void {
    Md5.hash(data, out, .{});
}

/// One-shot SHA1 hash
pub fn sha1Hash(data: []const u8, out: *[Sha1.digest_length]u8) void {
    Sha1.hash(data, out, .{});
}

/// One-shot SHA256 hash
pub fn sha256Hash(data: []const u8, out: *[Sha256.digest_length]u8) void {
    Sha256.hash(data, out, .{});
}

/// One-shot SHA512 hash
pub fn sha512Hash(data: []const u8, out: *[Sha512.digest_length]u8) void {
    Sha512.hash(data, out, .{});
}

/// Convert bytes to hex string
pub fn bytesToHex(bytes: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const hex = try allocator.alloc(u8, bytes.len * 2);
    const hex_chars = "0123456789abcdef";
    for (bytes, 0..) |byte, i| {
        hex[i * 2] = hex_chars[byte >> 4];
        hex[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return hex;
}

// ============================================================================
// Available algorithms (for hashlib.algorithms_available)
// ============================================================================

pub const algorithms_guaranteed = [_][]const u8{
    "md5",
    "sha1",
    "sha224",
    "sha256",
    "sha384",
    "sha512",
};

pub const algorithms_available = algorithms_guaranteed;
