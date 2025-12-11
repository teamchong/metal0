/// Hash Constants
/// Mirrors CPython's pyport.h hash constants
///
/// This module defines fundamental constants used throughout the Python hashing system.

const std = @import("std");

// ============================================================================
// Hash Type Definitions
// ============================================================================

/// Python's Py_hash_t type
pub const HashT = i64;

/// Python's Py_uhash_t type (unsigned)
pub const UHashT = u64;

// ============================================================================
// Hash Constants (matching CPython's pyport.h)
// ============================================================================

/// Number of bits in a hash value
pub const HASH_BITS: u6 = 61;

/// Modulus for hash calculations (Mersenne prime 2^61 - 1)
pub const HASH_MODULUS: u64 = (1 << HASH_BITS) - 1;

/// Hash value for positive infinity
pub const HASH_INF: i64 = 314159;

/// Hash value for NaN (pointer-based, but this is a fallback)
pub const HASH_NAN: i64 = 0;

/// Hash value for imaginary unit
pub const HASH_IMAG: i64 = 1000003;

/// Invalid hash value (signals error in CPython)
pub const HASH_INVALID: i64 = -1;

// ============================================================================
// Tests
// ============================================================================

test "hash constants" {
    try std.testing.expectEqual(@as(u6, 61), HASH_BITS);
    try std.testing.expectEqual(@as(u64, (1 << 61) - 1), HASH_MODULUS);
}
