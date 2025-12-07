/// bootstrap_hash - Bootstrap Hash Functions
/// Mirrors cpython/Python/bootstrap_hash.c
///
/// This module provides cryptographic hash functions for bootstrap:
/// - SipHash-2-4 for hash randomization
/// - CSPRNG for generating random hash seeds
/// - Platform-specific entropy sources

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// SipHash constants
const SIPHASH_ROUNDS_C = 2;
const SIPHASH_ROUNDS_D = 4;

/// Hash seed size
pub const HASH_SEED_SIZE: usize = 16;

/// Default hash cutoff for small strings
pub const HASH_CUTOFF: usize = 0;

// ============================================================================
// Hash Secret
// ============================================================================

/// Hash secret used for hash randomization
pub const HashSecret = struct {
    k0: u64 = 0,
    k1: u64 = 0,
    suffix: [16]u8 = [_]u8{0} ** 16,

    /// Initialize with random bytes
    pub fn initRandom(self: *HashSecret) void {
        var bytes: [32]u8 = undefined;
        std.crypto.random.bytes(&bytes);
        self.k0 = std.mem.readInt(u64, bytes[0..8], .little);
        self.k1 = std.mem.readInt(u64, bytes[8..16], .little);
        @memcpy(&self.suffix, bytes[16..32]);
    }

    /// Initialize with specific seed (for reproducibility)
    pub fn initSeed(self: *HashSecret, seed: u64) void {
        // Use seed to generate deterministic keys
        var state: u64 = seed;
        self.k0 = xorshift64(&state);
        self.k1 = xorshift64(&state);
        for (&self.suffix) |*b| {
            b.* = @truncate(xorshift64(&state));
        }
    }

    /// Initialize to zero (disabled)
    pub fn initZero(self: *HashSecret) void {
        self.k0 = 0;
        self.k1 = 0;
        self.suffix = [_]u8{0} ** 16;
    }
};

/// Global hash secret
var hash_secret: HashSecret = .{};
var hash_secret_initialized = false;

// ============================================================================
// SipHash Implementation
// ============================================================================

/// SipHash-2-4 implementation
pub fn sipHash24(key: [2]u64, data: []const u8) u64 {
    var v0: u64 = key[0] ^ 0x736f6d6570736575;
    var v1: u64 = key[1] ^ 0x646f72616e646f6d;
    var v2: u64 = key[0] ^ 0x6c7967656e657261;
    var v3: u64 = key[1] ^ 0x7465646279746573;

    // Process full blocks
    var i: usize = 0;
    while (i + 8 <= data.len) : (i += 8) {
        const m = std.mem.readInt(u64, data[i..][0..8], .little);
        v3 ^= m;
        inline for (0..SIPHASH_ROUNDS_C) |_| {
            sipRound(&v0, &v1, &v2, &v3);
        }
        v0 ^= m;
    }

    // Final block with length
    var last: u64 = @as(u64, @truncate(data.len)) << 56;
    const remaining = data.len - i;
    switch (remaining) {
        7 => last |= @as(u64, data[i + 6]) << 48,
        else => {},
    }
    if (remaining >= 6) last |= @as(u64, data[i + 5]) << 40;
    if (remaining >= 5) last |= @as(u64, data[i + 4]) << 32;
    if (remaining >= 4) last |= @as(u64, data[i + 3]) << 24;
    if (remaining >= 3) last |= @as(u64, data[i + 2]) << 16;
    if (remaining >= 2) last |= @as(u64, data[i + 1]) << 8;
    if (remaining >= 1) last |= @as(u64, data[i]);

    v3 ^= last;
    inline for (0..SIPHASH_ROUNDS_C) |_| {
        sipRound(&v0, &v1, &v2, &v3);
    }
    v0 ^= last;

    // Finalization
    v2 ^= 0xff;
    inline for (0..SIPHASH_ROUNDS_D) |_| {
        sipRound(&v0, &v1, &v2, &v3);
    }

    return v0 ^ v1 ^ v2 ^ v3;
}

/// SipHash round function
fn sipRound(v0: *u64, v1: *u64, v2: *u64, v3: *u64) void {
    v0.* +%= v1.*;
    v1.* = std.math.rotl(u64, v1.*, 13);
    v1.* ^= v0.*;
    v0.* = std.math.rotl(u64, v0.*, 32);

    v2.* +%= v3.*;
    v3.* = std.math.rotl(u64, v3.*, 16);
    v3.* ^= v2.*;

    v0.* +%= v3.*;
    v3.* = std.math.rotl(u64, v3.*, 21);
    v3.* ^= v0.*;

    v2.* +%= v1.*;
    v1.* = std.math.rotl(u64, v1.*, 17);
    v1.* ^= v2.*;
    v2.* = std.math.rotl(u64, v2.*, 32);
}

// ============================================================================
// FNV Hash (Fallback)
// ============================================================================

/// FNV-1a 64-bit hash
pub fn fnv1a64(data: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (data) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

/// FNV-1a 32-bit hash
pub fn fnv1a32(data: []const u8) u32 {
    var hash: u32 = 0x811c9dc5;
    for (data) |byte| {
        hash ^= byte;
        hash *%= 0x01000193;
    }
    return hash;
}

// ============================================================================
// Python Hash Functions
// ============================================================================

/// Hash bytes using the global secret
pub fn hashBytes(data: []const u8) u64 {
    ensureInitialized();
    return sipHash24(.{ hash_secret.k0, hash_secret.k1 }, data);
}

/// Hash string using the global secret
pub fn hashString(s: []const u8) i64 {
    if (s.len == 0) {
        return 0;
    }
    const h = hashBytes(s);
    // Convert to signed, avoid -1 (reserved for error)
    const result: i64 = @bitCast(h);
    return if (result == -1) -2 else result;
}

/// Hash pointer (for identity hashing)
pub fn hashPointer(ptr: *const anyopaque) u64 {
    const addr = @intFromPtr(ptr);
    // Rotate to mix high bits
    return std.math.rotl(u64, addr, 4);
}

/// Hash integer
pub fn hashInt(value: i64) i64 {
    // Python's integer hash
    if (value == -1) return -2;
    return value;
}

/// Hash u64 to i64
pub fn hashU64(value: u64) i64 {
    const result: i64 = @bitCast(value);
    return if (result == -1) -2 else result;
}

// ============================================================================
// Entropy Sources
// ============================================================================

/// Get entropy from OS CSPRNG
pub fn getRandomBytes(buf: []u8) !void {
    std.crypto.random.bytes(buf);
}

/// Get entropy with fallback
pub fn getEntropyWithFallback(buf: []u8) void {
    std.crypto.random.bytes(buf);
}

/// Get a single random u64
pub fn getRandomU64() u64 {
    var buf: [8]u8 = undefined;
    std.crypto.random.bytes(&buf);
    return std.mem.readInt(u64, &buf, .little);
}

// ============================================================================
// Hash Seed Management
// ============================================================================

/// Initialize hash secret from environment or random
pub fn initHashSecret() void {
    if (hash_secret_initialized) return;

    // Check for PYTHONHASHSEED environment variable
    if (std.posix.getenv("PYTHONHASHSEED")) |seed_str| {
        if (std.mem.eql(u8, seed_str, "random")) {
            hash_secret.initRandom();
        } else {
            const seed = std.fmt.parseInt(u64, seed_str, 10) catch 0;
            hash_secret.initSeed(seed);
        }
    } else {
        hash_secret.initRandom();
    }

    hash_secret_initialized = true;
}

/// Get current hash secret
pub fn getHashSecret() *const HashSecret {
    ensureInitialized();
    return &hash_secret;
}

/// Set hash secret (for testing)
pub fn setHashSecret(k0: u64, k1: u64) void {
    hash_secret.k0 = k0;
    hash_secret.k1 = k1;
    hash_secret_initialized = true;
}

/// Reset to uninitialized state (for testing)
pub fn resetHashSecret() void {
    hash_secret = .{};
    hash_secret_initialized = false;
}

fn ensureInitialized() void {
    if (!hash_secret_initialized) {
        initHashSecret();
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Xorshift64 PRNG
fn xorshift64(state: *u64) u64 {
    var x = state.*;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    state.* = x;
    return x;
}

/// Mix two hash values
pub fn hashCombine(h1: u64, h2: u64) u64 {
    return h1 ^ (h2 +% 0x9e3779b9 +% (h1 << 6) +% (h1 >> 2));
}

/// Hash tuple of values
pub fn hashTuple(hashes: []const i64) i64 {
    var result: u64 = 0x345678;
    for (hashes) |h| {
        result = hashCombine(result, @bitCast(h));
    }
    const final: i64 = @bitCast(result);
    return if (final == -1) -2 else final;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {
    initHashSecret();
}

// ============================================================================
// Tests
// ============================================================================

test "siphash basic" {
    const key = [2]u64{ 0x0706050403020100, 0x0f0e0d0c0b0a0908 };
    const data = "hello";
    const hash = sipHash24(key, data);
    try std.testing.expect(hash != 0);
}

test "siphash empty" {
    const key = [2]u64{ 0, 0 };
    const hash = sipHash24(key, "");
    try std.testing.expect(hash != 0);
}

test "fnv1a" {
    const hash1 = fnv1a64("hello");
    const hash2 = fnv1a64("world");
    try std.testing.expect(hash1 != hash2);

    // Empty string
    const empty = fnv1a64("");
    try std.testing.expect(empty == 0xcbf29ce484222325);
}

test "hash secret" {
    resetHashSecret();

    var secret: HashSecret = .{};
    secret.initSeed(12345);
    try std.testing.expect(secret.k0 != 0);
    try std.testing.expect(secret.k1 != 0);

    // Same seed produces same keys
    var secret2: HashSecret = .{};
    secret2.initSeed(12345);
    try std.testing.expectEqual(secret.k0, secret2.k0);
    try std.testing.expectEqual(secret.k1, secret2.k1);
}

test "hash string" {
    resetHashSecret();
    setHashSecret(1234, 5678);

    const h1 = hashString("hello");
    const h2 = hashString("world");
    try std.testing.expect(h1 != h2);

    // Same string, same hash
    const h3 = hashString("hello");
    try std.testing.expectEqual(h1, h3);

    // Empty string
    const empty = hashString("");
    try std.testing.expectEqual(@as(i64, 0), empty);
}

test "hash int" {
    try std.testing.expectEqual(@as(i64, 42), hashInt(42));
    try std.testing.expectEqual(@as(i64, -2), hashInt(-1)); // -1 becomes -2
    try std.testing.expectEqual(@as(i64, 0), hashInt(0));
}

test "hash combine" {
    const h1: u64 = 123456;
    const h2: u64 = 789012;
    const combined = hashCombine(h1, h2);
    try std.testing.expect(combined != h1);
    try std.testing.expect(combined != h2);
}

test "hash tuple" {
    const hashes = [_]i64{ 1, 2, 3 };
    const result = hashTuple(&hashes);
    try std.testing.expect(result != -1);

    // Different order = different hash
    const hashes2 = [_]i64{ 3, 2, 1 };
    const result2 = hashTuple(&hashes2);
    try std.testing.expect(result != result2);
}

test "random bytes" {
    var buf1: [16]u8 = undefined;
    var buf2: [16]u8 = undefined;
    try getRandomBytes(&buf1);
    try getRandomBytes(&buf2);
    // Extremely unlikely to be equal
    try std.testing.expect(!std.mem.eql(u8, &buf1, &buf2));
}
