/// Frozenset Hashing
/// Order-independent hash for frozensets
///
/// Uses XOR-based combination to ensure hash(frozenset{a,b,c})
/// is the same regardless of iteration order.

const std = @import("std");
const constants = @import("constants.zig");

const HashT = constants.HashT;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INVALID = constants.HASH_INVALID;

// ============================================================================
// Frozenset Hashing
// ============================================================================

/// Hash for frozensets (order-independent)
pub fn hashFrozenset(hashes: []const HashT) HashT {
    var hash: u64 = 0;

    for (hashes) |h| {
        // XOR-based combination (order independent)
        const v: u64 = @bitCast(h);
        hash ^= (v ^ (v << 16) ^ 89869747) *% 3644798167;
    }

    // Finalize
    hash = hash *% 69069 +% 907133923;

    var result: HashT = @intCast(hash % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "hash frozenset" {
    const hashes = [_]HashT{ 1, 2, 3 };
    const h1 = hashFrozenset(&hashes);

    // Order should not matter for frozenset
    const hashes2 = [_]HashT{ 3, 1, 2 };
    const h2 = hashFrozenset(&hashes2);
    try std.testing.expectEqual(h1, h2);
}
