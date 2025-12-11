/// FNV-1a Hash
/// Fallback/alternative hash algorithm
///
/// FNV-1a is a simpler, faster hash algorithm used as a fallback
/// when SipHash is not needed.

const std = @import("std");
const secret = @import("secret.zig");

// ============================================================================
// FNV-1a Constants
// ============================================================================

/// FNV-1a hash constants
const FNV_OFFSET_BASIS: u64 = 14695981039346656037;
const FNV_PRIME: u64 = 1099511628211;

// ============================================================================
// FNV-1a Hash
// ============================================================================

/// Compute FNV-1a hash
pub fn fnvHash(data: []const u8) u64 {
    var hash = FNV_OFFSET_BASIS ^ secret.getHashSecret().fnv_seed;
    for (data) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }
    return hash;
}
