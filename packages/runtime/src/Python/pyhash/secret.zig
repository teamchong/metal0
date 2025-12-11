/// Hash Secret Management
/// Provides cryptographically secure random seeds for SipHash
///
/// This module manages the global hash secret used to randomize hashing
/// and protect against hash collision attacks.

const std = @import("std");

// ============================================================================
// Hash Secret Structure
// ============================================================================

/// Hash secret structure for SipHash
pub const HashSecret = struct {
    /// SipHash key parts
    k0: u64,
    k1: u64,

    /// FNV seed (for non-SipHash fallback)
    fnv_seed: u64,

    /// Whether the secret has been initialized
    initialized: bool,
};

/// Global hash secret (thread-safe via threadlocal)
threadlocal var hash_secret: HashSecret = .{
    .k0 = 0,
    .k1 = 0,
    .fnv_seed = 0,
    .initialized = false,
};

// ============================================================================
// Hash Secret Functions
// ============================================================================

/// Initialize hash secret with random bytes
pub fn initHashSecret() void {
    if (hash_secret.initialized) return;

    // Get random bytes from OS
    var buf: [24]u8 = undefined;
    std.crypto.random.bytes(&buf);

    hash_secret.k0 = std.mem.readInt(u64, buf[0..8], .little);
    hash_secret.k1 = std.mem.readInt(u64, buf[8..16], .little);
    hash_secret.fnv_seed = std.mem.readInt(u64, buf[16..24], .little);
    hash_secret.initialized = true;
}

/// Get the current hash secret
pub fn getHashSecret() *const HashSecret {
    if (!hash_secret.initialized) {
        initHashSecret();
    }
    return &hash_secret;
}

/// Set hash secret (for reproducible hashing, e.g., PYTHONHASHSEED)
pub fn setHashSecret(k0: u64, k1: u64) void {
    hash_secret.k0 = k0;
    hash_secret.k1 = k1;
    hash_secret.fnv_seed = k0 ^ k1;
    hash_secret.initialized = true;
}

/// Initialize hash module
pub fn init() void {
    initHashSecret();
}
