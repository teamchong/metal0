/// SipHash-2-4 Implementation
/// Fast, cryptographically strong pseudo-random function
///
/// This module implements SipHash-2-4, the hash algorithm used by Python
/// for string and bytes hashing to protect against collision attacks.

const std = @import("std");
const secret = @import("secret.zig");

// ============================================================================
// SipHash State
// ============================================================================

/// SipHash state
const SipState = struct {
    v0: u64,
    v1: u64,
    v2: u64,
    v3: u64,

    const Self = @This();

    fn init(k0: u64, k1: u64) Self {
        return .{
            .v0 = k0 ^ 0x736f6d6570736575,
            .v1 = k1 ^ 0x646f72616e646f6d,
            .v2 = k0 ^ 0x6c7967656e657261,
            .v3 = k1 ^ 0x7465646279746573,
        };
    }

    fn sipRound(self: *Self) void {
        self.v0 +%= self.v1;
        self.v1 = std.math.rotl(u64, self.v1, 13);
        self.v1 ^= self.v0;
        self.v0 = std.math.rotl(u64, self.v0, 32);
        self.v2 +%= self.v3;
        self.v3 = std.math.rotl(u64, self.v3, 16);
        self.v3 ^= self.v2;
        self.v0 +%= self.v3;
        self.v3 = std.math.rotl(u64, self.v3, 21);
        self.v3 ^= self.v0;
        self.v2 +%= self.v1;
        self.v1 = std.math.rotl(u64, self.v1, 17);
        self.v1 ^= self.v2;
        self.v2 = std.math.rotl(u64, self.v2, 32);
    }

    fn compress(self: *Self, m: u64) void {
        self.v3 ^= m;
        self.sipRound();
        self.sipRound();
        self.v0 ^= m;
    }

    fn finalize(self: *Self) u64 {
        self.v2 ^= 0xff;
        self.sipRound();
        self.sipRound();
        self.sipRound();
        self.sipRound();
        return self.v0 ^ self.v1 ^ self.v2 ^ self.v3;
    }
};

// ============================================================================
// Public API
// ============================================================================

/// Compute SipHash-2-4 of a byte buffer
pub fn sipHash24(data: []const u8) u64 {
    const hash_secret = secret.getHashSecret();
    var state = SipState.init(hash_secret.k0, hash_secret.k1);

    const len = data.len;
    var i: usize = 0;

    // Process 8-byte blocks
    while (i + 8 <= len) : (i += 8) {
        const m = std.mem.readInt(u64, data[i..][0..8], .little);
        state.compress(m);
    }

    // Handle remaining bytes
    var last: u64 = @as(u64, @intCast(len & 0xff)) << 56;
    const remaining = len - i;

    if (remaining >= 7) last |= @as(u64, data[i + 6]) << 48;
    if (remaining >= 6) last |= @as(u64, data[i + 5]) << 40;
    if (remaining >= 5) last |= @as(u64, data[i + 4]) << 32;
    if (remaining >= 4) last |= @as(u64, data[i + 3]) << 24;
    if (remaining >= 3) last |= @as(u64, data[i + 2]) << 16;
    if (remaining >= 2) last |= @as(u64, data[i + 1]) << 8;
    if (remaining >= 1) last |= @as(u64, data[i]);

    state.compress(last);
    return state.finalize();
}

// ============================================================================
// Tests
// ============================================================================

test "siphash" {
    secret.initHashSecret();

    // Same input should give same output
    const h1 = sipHash24("test");
    const h2 = sipHash24("test");
    try std.testing.expectEqual(h1, h2);
}
