/// Hash Info
/// Information about the hash algorithm (for sys.hash_info)
///
/// Provides runtime information about the hashing implementation.

const constants = @import("constants.zig");

const HASH_BITS = constants.HASH_BITS;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INF = constants.HASH_INF;
const HASH_NAN = constants.HASH_NAN;
const HASH_IMAG = constants.HASH_IMAG;

// ============================================================================
// Hash Info Structure
// ============================================================================

/// Hash algorithm information
pub const HashInfo = struct {
    width: u32,
    modulus: u64,
    inf: i64,
    nan: i64,
    imag: i64,
    algorithm: []const u8,
    hash_bits: u32,
    seed_bits: u32,
};

/// Get hash info (matches sys.hash_info)
pub fn getHashInfo() HashInfo {
    return .{
        .width = 64,
        .modulus = HASH_MODULUS,
        .inf = HASH_INF,
        .nan = HASH_NAN,
        .imag = HASH_IMAG,
        .algorithm = "siphash24",
        .hash_bits = HASH_BITS,
        .seed_bits = 128,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "hash info" {
    const std = @import("std");
    const info = getHashInfo();
    try std.testing.expectEqual(@as(u32, 64), info.width);
    try std.testing.expectEqual(HASH_MODULUS, info.modulus);
    try std.testing.expectEqualStrings("siphash24", info.algorithm);
}
