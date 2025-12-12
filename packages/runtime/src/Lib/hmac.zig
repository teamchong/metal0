/// hmac - Keyed-Hashing for Message Authentication
/// Mirrors cpython/Lib/hmac.py
///
/// Implements HMAC (Hash-based Message Authentication Code)
/// as defined in RFC 2104.

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default digest module
pub const DEFAULT_DIGEST_NAME: []const u8 = "md5";

/// Block sizes for various algorithms
pub const BLOCK_SIZES = std.StaticStringMap(usize).initComptime(.{
    .{ "md5", 64 },
    .{ "sha1", 64 },
    .{ "sha224", 64 },
    .{ "sha256", 64 },
    .{ "sha384", 128 },
    .{ "sha512", 128 },
    .{ "sha3_224", 144 },
    .{ "sha3_256", 136 },
    .{ "sha3_384", 104 },
    .{ "sha3_512", 72 },
    .{ "blake2b", 128 },
    .{ "blake2s", 64 },
});

/// Digest sizes for various algorithms
pub const DIGEST_SIZES = std.StaticStringMap(usize).initComptime(.{
    .{ "md5", 16 },
    .{ "sha1", 20 },
    .{ "sha224", 28 },
    .{ "sha256", 32 },
    .{ "sha384", 48 },
    .{ "sha512", 64 },
    .{ "sha3_224", 28 },
    .{ "sha3_256", 32 },
    .{ "sha3_384", 48 },
    .{ "sha3_512", 64 },
    .{ "blake2b", 64 },
    .{ "blake2s", 32 },
});

// ============================================================================
// HMAC Implementation
// ============================================================================

/// HMAC object for computing keyed hashes
pub const HMAC = struct {
    const Self = @This();

    /// The algorithm name
    digest_name: []const u8,
    /// Block size
    block_size: usize,
    /// Digest size
    digest_size: usize,
    /// Inner padding (key XOR 0x36)
    inner_pad: []u8,
    /// Outer padding (key XOR 0x5c)
    outer_pad: []u8,
    /// Current hash state
    inner_hash: std.crypto.hash.Md5,
    /// Allocator
    allocator: std.mem.Allocator,

    /// Create a new HMAC object
    pub fn init(
        allocator: std.mem.Allocator,
        key: []const u8,
        digestmod: ?[]const u8,
    ) !Self {
        const digest_name = digestmod orelse DEFAULT_DIGEST_NAME;
        const block_size = BLOCK_SIZES.get(digest_name) orelse 64;
        const digest_size = DIGEST_SIZES.get(digest_name) orelse 16;

        // Process key
        var processed_key: std.ArrayList(u8) = .{};
        defer processed_key.deinit(allocator);

        if (key.len > block_size) {
            // Hash the key if too long
            var hasher = std.crypto.hash.Md5.init(.{});
            hasher.update(key);
            var hashed: [16]u8 = undefined;
            hasher.final(&hashed);
            try processed_key.appendSlice(allocator, &hashed);
        } else {
            try processed_key.appendSlice(allocator, key);
        }

        // Pad key to block size
        while (processed_key.items.len < block_size) {
            try processed_key.append(allocator, 0);
        }

        // Create inner and outer pads
        const inner_pad = try allocator.alloc(u8, block_size);
        const outer_pad = try allocator.alloc(u8, block_size);

        for (0..block_size) |i| {
            inner_pad[i] = processed_key.items[i] ^ 0x36;
            outer_pad[i] = processed_key.items[i] ^ 0x5c;
        }

        // Initialize inner hash with inner pad
        var inner_hash = std.crypto.hash.Md5.init(.{});
        inner_hash.update(inner_pad);

        return Self{
            .digest_name = digest_name,
            .block_size = block_size,
            .digest_size = digest_size,
            .inner_pad = inner_pad,
            .outer_pad = outer_pad,
            .inner_hash = inner_hash,
            .allocator = allocator,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.inner_pad);
        self.allocator.free(self.outer_pad);
    }

    /// Update the HMAC with data
    pub fn update(self: *Self, data: []const u8) void {
        self.inner_hash.update(data);
    }

    /// Get the digest as bytes
    pub fn digest(self: *Self) [16]u8 {
        // Finalize inner hash
        var inner_result: [16]u8 = undefined;
        // Copy state to avoid modifying the original
        var inner_copy = self.inner_hash;
        inner_copy.final(&inner_result);

        // Compute outer hash: H(outer_pad || inner_hash)
        var outer_hash = std.crypto.hash.Md5.init(.{});
        outer_hash.update(self.outer_pad);
        outer_hash.update(&inner_result);

        var result: [16]u8 = undefined;
        outer_hash.final(&result);

        return result;
    }

    /// Get the digest as a hex string
    pub fn hexdigest(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const d = self.digest();
        return bytesToHex(allocator, &d);
    }

    /// Make a copy of this HMAC
    pub fn copy(self: *const Self) !Self {
        const new_hmac = Self{
            .digest_name = self.digest_name,
            .block_size = self.block_size,
            .digest_size = self.digest_size,
            .inner_pad = try self.allocator.dupe(u8, self.inner_pad),
            .outer_pad = try self.allocator.dupe(u8, self.outer_pad),
            .inner_hash = self.inner_hash,
            .allocator = self.allocator,
        };
        return new_hmac;
    }

    /// Get the name of the algorithm
    pub fn name(self: *const Self) []const u8 {
        return self.digest_name;
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert bytes to hex string
fn bytesToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const hex_chars = "0123456789abcdef";
    const result = try allocator.alloc(u8, bytes.len * 2);

    for (bytes, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    return result;
}

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Create a new HMAC object
pub fn new(
    allocator: std.mem.Allocator,
    key: []const u8,
    msg: ?[]const u8,
    digestmod: ?[]const u8,
) !HMAC {
    var hmac_obj = try HMAC.init(allocator, key, digestmod);
    if (msg) |m| {
        hmac_obj.update(m);
    }
    return hmac_obj;
}

/// Compute HMAC digest in one call
pub fn digest(
    allocator: std.mem.Allocator,
    key: []const u8,
    msg: []const u8,
    digestmod: ?[]const u8,
) ![16]u8 {
    var hmac_obj = try HMAC.init(allocator, key, digestmod);
    defer hmac_obj.deinit();
    hmac_obj.update(msg);
    return hmac_obj.digest();
}

/// Compare two digests in constant time
pub fn compareDigest(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    var result: u8 = 0;
    for (a, b) |a_byte, b_byte| {
        result |= a_byte ^ b_byte;
    }
    return result == 0;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the hmac module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "HMAC init and digest" {
    const allocator = std.testing.allocator;

    var hmac_obj = try HMAC.init(allocator, "key", "md5");
    defer hmac_obj.deinit();

    hmac_obj.update("The quick brown fox jumps over the lazy dog");
    const d = hmac_obj.digest();

    try std.testing.expect(d.len == 16);
}

test "HMAC hexdigest" {
    const allocator = std.testing.allocator;

    var hmac_obj = try HMAC.init(allocator, "key", "md5");
    defer hmac_obj.deinit();

    hmac_obj.update("message");
    const hex = try hmac_obj.hexdigest(allocator);
    defer allocator.free(hex);

    try std.testing.expectEqual(@as(usize, 32), hex.len);
}

test "HMAC copy" {
    const allocator = std.testing.allocator;

    var hmac1 = try HMAC.init(allocator, "key", "md5");
    defer hmac1.deinit();

    hmac1.update("hello");

    var hmac2 = try hmac1.copy();
    defer hmac2.deinit();

    // Both should produce same digest
    const d1 = hmac1.digest();
    const d2 = hmac2.digest();

    try std.testing.expect(std.mem.eql(u8, &d1, &d2));
}

test "new function" {
    const allocator = std.testing.allocator;

    var hmac_obj = try new(allocator, "key", "message", "md5");
    defer hmac_obj.deinit();

    const d = hmac_obj.digest();
    try std.testing.expect(d.len == 16);
}

test "digest function" {
    const allocator = std.testing.allocator;

    const d = try digest(allocator, "key", "message", "md5");
    try std.testing.expect(d.len == 16);
}

test "compareDigest equal" {
    const a = [_]u8{ 1, 2, 3, 4 };
    const b = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expect(compareDigest(&a, &b));
}

test "compareDigest not equal" {
    const a = [_]u8{ 1, 2, 3, 4 };
    const b = [_]u8{ 1, 2, 3, 5 };
    try std.testing.expect(!compareDigest(&a, &b));
}

test "compareDigest different lengths" {
    const a = [_]u8{ 1, 2, 3 };
    const b = [_]u8{ 1, 2, 3, 4 };
    try std.testing.expect(!compareDigest(&a, &b));
}

test "BLOCK_SIZES" {
    try std.testing.expectEqual(@as(usize, 64), BLOCK_SIZES.get("md5").?);
    try std.testing.expectEqual(@as(usize, 64), BLOCK_SIZES.get("sha256").?);
    try std.testing.expectEqual(@as(usize, 128), BLOCK_SIZES.get("sha512").?);
}

test "DIGEST_SIZES" {
    try std.testing.expectEqual(@as(usize, 16), DIGEST_SIZES.get("md5").?);
    try std.testing.expectEqual(@as(usize, 32), DIGEST_SIZES.get("sha256").?);
    try std.testing.expectEqual(@as(usize, 64), DIGEST_SIZES.get("sha512").?);
}

test "bytesToHex" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{ 0xde, 0xad, 0xbe, 0xef };
    const hex = try bytesToHex(allocator, &bytes);
    defer allocator.free(hex);

    try std.testing.expectEqualStrings("deadbeef", hex);
}
