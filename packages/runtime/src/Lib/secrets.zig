//! CPython source: Lib/secrets.py
//!
//! Generate cryptographically strong random numbers suitable for
//! managing secrets such as account authentication, tokens, and similar.
//!
//! Mirrors: CPython Lib/secrets.py

const std = @import("std");

// ============================================================================
// Random number generation
// ============================================================================

/// Default token size in bytes
pub const DEFAULT_ENTROPY = 32;

/// Cryptographically secure random number generator
const SecureRandom = std.crypto.random;

/// Return a random byte string containing nbytes random bytes
pub fn token_bytes(nbytes: ?usize) []const u8 {
    const n = nbytes orelse DEFAULT_ENTROPY;
    var buffer: [256]u8 = undefined;
    const actual_n = @min(n, buffer.len);
    SecureRandom.bytes(buffer[0..actual_n]);
    return buffer[0..actual_n];
}

/// Return a random byte string containing nbytes bytes, allocated
pub fn token_bytes_alloc(allocator: std.mem.Allocator, nbytes: ?usize) ![]u8 {
    const n = nbytes orelse DEFAULT_ENTROPY;
    var buffer = try allocator.alloc(u8, n);
    SecureRandom.bytes(buffer);
    return buffer;
}

/// Return a random text string, in hexadecimal
pub fn token_hex(allocator: std.mem.Allocator, nbytes: ?usize) ![]u8 {
    const n = nbytes orelse DEFAULT_ENTROPY;
    var rand_bytes = try allocator.alloc(u8, n);
    defer allocator.free(rand_bytes);

    SecureRandom.bytes(rand_bytes);

    var result = try allocator.alloc(u8, n * 2);
    errdefer allocator.free(result);

    const hex_chars = "0123456789abcdef";
    for (rand_bytes, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }

    return result;
}

/// Return a random URL-safe text string containing nbytes random bytes
pub fn token_urlsafe(allocator: std.mem.Allocator, nbytes: ?usize) ![]u8 {
    const n = nbytes orelse DEFAULT_ENTROPY;
    var rand_bytes = try allocator.alloc(u8, n);
    defer allocator.free(rand_bytes);

    SecureRandom.bytes(rand_bytes);

    // Base64 URL-safe encoding
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    // Calculate output size (base64 expands 3 bytes to 4 chars)
    const out_len = ((n + 2) / 3) * 4;
    var result = try allocator.alloc(u8, out_len);
    errdefer allocator.free(result);

    var i: usize = 0;
    var j: usize = 0;
    while (i < n) : (i += 3) {
        const b0 = rand_bytes[i];
        const b1 = if (i + 1 < n) rand_bytes[i + 1] else 0;
        const b2 = if (i + 2 < n) rand_bytes[i + 2] else 0;

        result[j] = alphabet[@as(usize, b0 >> 2)];
        result[j + 1] = alphabet[@as(usize, ((b0 & 0x03) << 4) | (b1 >> 4))];
        result[j + 2] = if (i + 1 < n) alphabet[@as(usize, ((b1 & 0x0f) << 2) | (b2 >> 6))] else '=';
        result[j + 3] = if (i + 2 < n) alphabet[@as(usize, b2 & 0x3f)] else '=';
        j += 4;
    }

    // Trim trailing '=' padding
    while (j > 0 and result[j - 1] == '=') {
        j -= 1;
    }

    return allocator.realloc(result, j) catch result[0..j];
}

// ============================================================================
// Random number generation
// ============================================================================

/// Return a random integer in the range [0, n)
pub fn randbelow(exclusive_upper_bound: u64) u64 {
    if (exclusive_upper_bound == 0) return 0;
    return SecureRandom.uintLessThan(u64, exclusive_upper_bound);
}

/// Return a randomly chosen element from a non-empty sequence
pub fn choice(comptime T: type, seq: []const T) T {
    if (seq.len == 0) {
        @panic("choice from empty sequence");
    }
    const index = randbelow(seq.len);
    return seq[index];
}

/// Return a random integer N such that a <= N <= b
pub fn randbits(k: u6) u64 {
    if (k == 0) return 0;
    var result: u64 = 0;
    SecureRandom.bytes(std.mem.asBytes(&result));
    return result >> @as(u6, @intCast(64 - k));
}

// ============================================================================
// Comparison functions
// ============================================================================

/// Return True if strings a and b are equal, False otherwise.
/// Uses constant-time comparison to prevent timing attacks.
pub fn compare_digest(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    var result: u8 = 0;
    for (a, b) |x, y| {
        result |= x ^ y;
    }
    return result == 0;
}

// ============================================================================
// Password/token generation helpers
// ============================================================================

/// Generate a secure random password of given length
pub fn generate_password(allocator: std.mem.Allocator, length: usize, options: PasswordOptions) ![]u8 {
    var charset: std.ArrayList(u8) = .{};
    defer charset.deinit(allocator);

    if (options.lowercase) {
        try charset.appendSlice(allocator, "abcdefghijklmnopqrstuvwxyz");
    }
    if (options.uppercase) {
        try charset.appendSlice(allocator, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    }
    if (options.digits) {
        try charset.appendSlice(allocator, "0123456789");
    }
    if (options.special) {
        try charset.appendSlice(allocator, "!@#$%^&*()_+-=[]{}|;:,.<>?");
    }

    if (charset.items.len == 0) {
        return error.EmptyCharset;
    }

    var result = try allocator.alloc(u8, length);
    errdefer allocator.free(result);

    for (result) |*c| {
        c.* = choice(u8, charset.items);
    }

    return result;
}

pub const PasswordOptions = struct {
    lowercase: bool = true,
    uppercase: bool = true,
    digits: bool = true,
    special: bool = false,
};

/// Generate a secure API key
pub fn generate_api_key(allocator: std.mem.Allocator) ![]u8 {
    return token_hex(allocator, 32);
}

/// Generate a secure session token
pub fn generate_session_token(allocator: std.mem.Allocator) ![]u8 {
    return token_urlsafe(allocator, 32);
}

// ============================================================================
// System entropy
// ============================================================================

/// Get system entropy bytes
/// Uses std.crypto.random which accesses OS entropy sources:
/// - Linux: getrandom() or /dev/urandom
/// - macOS: getentropy()
/// - Windows: RtlGenRandom()
pub fn getentropy(allocator: std.mem.Allocator, n: usize) ![]u8 {
    const buf = try allocator.alloc(u8, n);
    std.crypto.random.bytes(buf);
    return buf;
}

// ============================================================================
// Tests
// ============================================================================

test "token_hex" {
    const allocator = std.testing.allocator;

    const hex = try token_hex(allocator, 16);
    defer allocator.free(hex);

    try std.testing.expectEqual(@as(usize, 32), hex.len);

    // All chars should be hex
    for (hex) |c| {
        try std.testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
    }
}

test "token_urlsafe" {
    const allocator = std.testing.allocator;

    const token = try token_urlsafe(allocator, 16);
    defer allocator.free(token);

    // URL-safe base64 chars
    for (token) |c| {
        try std.testing.expect(
            (c >= 'A' and c <= 'Z') or
                (c >= 'a' and c <= 'z') or
                (c >= '0' and c <= '9') or
                c == '-' or c == '_',
        );
    }
}

test "randbelow" {
    for (0..100) |_| {
        const r = randbelow(10);
        try std.testing.expect(r < 10);
    }
}

test "choice" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    for (0..100) |_| {
        const c = choice(i32, &items);
        try std.testing.expect(c >= 1 and c <= 5);
    }
}

test "compare_digest" {
    try std.testing.expect(compare_digest("hello", "hello"));
    try std.testing.expect(!compare_digest("hello", "world"));
    try std.testing.expect(!compare_digest("hello", "hell"));
}

test "generate_password" {
    const allocator = std.testing.allocator;

    const pw = try generate_password(allocator, 16, .{});
    defer allocator.free(pw);

    try std.testing.expectEqual(@as(usize, 16), pw.len);
}

test "randbits" {
    for (0..100) |_| {
        const r = randbits(8);
        try std.testing.expect(r < 256);
    }

    const r1 = randbits(1);
    try std.testing.expect(r1 < 2);
}
