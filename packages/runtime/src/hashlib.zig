/// Hashlib - Cryptographic Hash Functions
/// Python-compatible API for hashlib module
const std = @import("std");

// Use Zig's built-in crypto
const Md5 = std.crypto.hash.Md5;
const Sha1 = std.crypto.hash.Sha1;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Sha512 = std.crypto.hash.sha2.Sha512;
const Sha384 = std.crypto.hash.sha2.Sha384;
const Sha224 = std.crypto.hash.sha2.Sha224;

/// Generic hash object interface
pub const HashObject = struct {
    algorithm: Algorithm,
    // Internal state stored as bytes (union would be cleaner but this is simpler)
    state: [256]u8,
    state_len: usize,
    digest_size: usize,
    block_size: usize,
    name: []const u8,

    pub const Algorithm = enum {
        md5,
        sha1,
        sha224,
        sha256,
        sha384,
        sha512,
    };

    /// Update hash with more data
    pub fn update(self: *HashObject, data: []const u8) void {
        switch (self.algorithm) {
            .md5 => {
                var hasher = @as(*Md5, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
            .sha1 => {
                var hasher = @as(*Sha1, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
            .sha224 => {
                var hasher = @as(*Sha224, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
            .sha256 => {
                var hasher = @as(*Sha256, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
            .sha384 => {
                var hasher = @as(*Sha384, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
            .sha512 => {
                var hasher = @as(*Sha512, @ptrCast(@alignCast(&self.state)));
                hasher.update(data);
            },
        }
    }

    /// Get the digest as bytes
    pub fn digest(self: *HashObject) []const u8 {
        var result: [64]u8 = undefined;
        switch (self.algorithm) {
            .md5 => {
                var hasher = @as(*Md5, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..16], &d);
                return result[0..16];
            },
            .sha1 => {
                var hasher = @as(*Sha1, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..20], &d);
                return result[0..20];
            },
            .sha224 => {
                var hasher = @as(*Sha224, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..28], &d);
                return result[0..28];
            },
            .sha256 => {
                var hasher = @as(*Sha256, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..32], &d);
                return result[0..32];
            },
            .sha384 => {
                var hasher = @as(*Sha384, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..48], &d);
                return result[0..48];
            },
            .sha512 => {
                var hasher = @as(*Sha512, @ptrCast(@alignCast(&self.state)));
                const d = hasher.finalResult();
                @memcpy(result[0..64], &d);
                return result[0..64];
            },
        }
    }

    /// Get the digest as hex string
    pub fn hexdigest(self: *HashObject, allocator: std.mem.Allocator) ![]u8 {
        const d = self.digest();
        const hex = try allocator.alloc(u8, d.len * 2);
        const hex_chars = "0123456789abcdef";
        for (d, 0..) |byte, i| {
            hex[i * 2] = hex_chars[byte >> 4];
            hex[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        return hex;
    }

    /// Copy the hash object
    pub fn copy(self: *const HashObject) HashObject {
        var new_obj = HashObject{
            .algorithm = self.algorithm,
            .state = undefined,
            .state_len = self.state_len,
            .digest_size = self.digest_size,
            .block_size = self.block_size,
            .name = self.name,
        };
        @memcpy(&new_obj.state, &self.state);
        return new_obj;
    }
};

/// Create MD5 hash object
pub fn md5() HashObject {
    var obj = HashObject{
        .algorithm = .md5,
        .state = undefined,
        .state_len = @sizeOf(Md5),
        .digest_size = 16,
        .block_size = 64,
        .name = "md5",
    };
    const hasher = @as(*Md5, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Md5.init(.{});
    return obj;
}

/// Create SHA1 hash object
pub fn sha1() HashObject {
    var obj = HashObject{
        .algorithm = .sha1,
        .state = undefined,
        .state_len = @sizeOf(Sha1),
        .digest_size = 20,
        .block_size = 64,
        .name = "sha1",
    };
    const hasher = @as(*Sha1, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Sha1.init(.{});
    return obj;
}

/// Create SHA224 hash object
pub fn sha224() HashObject {
    var obj = HashObject{
        .algorithm = .sha224,
        .state = undefined,
        .state_len = @sizeOf(Sha224),
        .digest_size = 28,
        .block_size = 64,
        .name = "sha224",
    };
    const hasher = @as(*Sha224, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Sha224.init(.{});
    return obj;
}

/// Create SHA256 hash object
pub fn sha256() HashObject {
    var obj = HashObject{
        .algorithm = .sha256,
        .state = undefined,
        .state_len = @sizeOf(Sha256),
        .digest_size = 32,
        .block_size = 64,
        .name = "sha256",
    };
    const hasher = @as(*Sha256, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Sha256.init(.{});
    return obj;
}

/// Create SHA384 hash object
pub fn sha384() HashObject {
    var obj = HashObject{
        .algorithm = .sha384,
        .state = undefined,
        .state_len = @sizeOf(Sha384),
        .digest_size = 48,
        .block_size = 128,
        .name = "sha384",
    };
    const hasher = @as(*Sha384, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Sha384.init(.{});
    return obj;
}

/// Create SHA512 hash object
pub fn sha512() HashObject {
    var obj = HashObject{
        .algorithm = .sha512,
        .state = undefined,
        .state_len = @sizeOf(Sha512),
        .digest_size = 64,
        .block_size = 128,
        .name = "sha512",
    };
    const hasher = @as(*Sha512, @ptrCast(@alignCast(&obj.state)));
    hasher.* = Sha512.init(.{});
    return obj;
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
pub fn md5Hash(data: []const u8) [16]u8 {
    return Md5.hash(data, .{});
}

/// One-shot SHA1 hash
pub fn sha1Hash(data: []const u8) [20]u8 {
    return Sha1.hash(data, .{});
}

/// One-shot SHA256 hash
pub fn sha256Hash(data: []const u8) [32]u8 {
    return Sha256.hash(data, .{});
}

/// One-shot SHA512 hash
pub fn sha512Hash(data: []const u8) [64]u8 {
    return Sha512.hash(data, .{});
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
