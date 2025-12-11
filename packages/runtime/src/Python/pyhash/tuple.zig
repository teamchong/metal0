/// Tuple Hashing
/// Order-dependent hash for tuples
///
/// Uses xxHash-based combination for fast, deterministic hashing
/// where element order matters.

const std = @import("std");
const constants = @import("constants.zig");

const HashT = constants.HashT;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INVALID = constants.HASH_INVALID;

// ============================================================================
// Tuple Hash Constants
// ============================================================================

/// xxHash-based tuple hash multiplier
const TUPLE_HASH_MULT: u64 = 0xc2b2ae3d27d4eb4f;

// ============================================================================
// Tuple Hashing
// ============================================================================

/// Hash a tuple of hash values
pub fn hashTuple(hashes: []const HashT) HashT {
    var acc: u64 = 0x27d4eb2f165667c5; // Initial accumulator

    for (hashes) |h| {
        const lane: u64 = @bitCast(h);
        acc +%= lane *% TUPLE_HASH_MULT;
        acc = std.math.rotl(u64, acc, 31);
    }

    // Finalize
    acc +%= @as(u64, @intCast(hashes.len)) *% TUPLE_HASH_MULT;
    acc ^= acc >> 33;
    acc *%= 0xff51afd7ed558ccd;
    acc ^= acc >> 33;
    acc *%= 0xc4ceb9fe1a85ec53;
    acc ^= acc >> 33;

    var result: HashT = @intCast(acc % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "hash tuple" {
    const hashes = [_]HashT{ 1, 2, 3 };
    const h1 = hashTuple(&hashes);
    const h2 = hashTuple(&hashes);
    try std.testing.expectEqual(h1, h2);

    // Different order should produce different hash
    const hashes2 = [_]HashT{ 3, 2, 1 };
    const h3 = hashTuple(&hashes2);
    try std.testing.expect(h1 != h3);
}
