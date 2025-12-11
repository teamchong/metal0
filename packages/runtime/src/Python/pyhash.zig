/// pyhash - Python Hash Functions
/// Mirrors cpython/Python/pyhash.c
///
/// This module provides hash utility functions for Python objects:
/// - Numeric hashing (integers, floats, complex)
/// - String/bytes hashing (SipHash-2-4)
/// - Pointer hashing
/// - Hash secret management
///
/// The key invariant is: if a == b then hash(a) == hash(b)

// ============================================================================
// Re-exports from submodules
// ============================================================================

// Constants
pub const constants = @import("pyhash/constants.zig");
pub const HASH_BITS = constants.HASH_BITS;
pub const HASH_MODULUS = constants.HASH_MODULUS;
pub const HASH_INF = constants.HASH_INF;
pub const HASH_NAN = constants.HASH_NAN;
pub const HASH_IMAG = constants.HASH_IMAG;
pub const HASH_INVALID = constants.HASH_INVALID;
pub const HashT = constants.HashT;
pub const UHashT = constants.UHashT;

// Secret management
pub const secret = @import("pyhash/secret.zig");
pub const HashSecret = secret.HashSecret;
pub const initHashSecret = secret.initHashSecret;
pub const getHashSecret = secret.getHashSecret;
pub const setHashSecret = secret.setHashSecret;

// SipHash
pub const siphash = @import("pyhash/siphash.zig");
pub const sipHash24 = siphash.sipHash24;

// String/bytes hashing
pub const string = @import("pyhash/string.zig");
pub const hashBuffer = string.hashBuffer;
pub const hashString = string.hashString;

// Numeric hashing
pub const numeric = @import("pyhash/numeric.zig");
pub const hashLong = numeric.hashLong;
pub const hashDouble = numeric.hashDouble;
pub const hashComplex = numeric.hashComplex;

// Pointer hashing
pub const pointer = @import("pyhash/pointer.zig");
pub const hashPointer = pointer.hashPointer;
pub const hashPointerRaw = pointer.hashPointerRaw;

// FNV-1a
pub const fnv = @import("pyhash/fnv.zig");
pub const fnvHash = fnv.fnvHash;

// Tuple hashing
pub const tuple = @import("pyhash/tuple.zig");
pub const hashTuple = tuple.hashTuple;

// Frozenset hashing
pub const frozenset = @import("pyhash/frozenset.zig");
pub const hashFrozenset = frozenset.hashFrozenset;

// Hash info
pub const hash_info = @import("pyhash/hash_info.zig");
pub const HashInfo = hash_info.HashInfo;
pub const getHashInfo = hash_info.getHashInfo;

// Generic hashing
pub const generic = @import("pyhash/generic.zig");
pub const hashAny = generic.hashAny;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize hash module
pub fn init() void {
    secret.init();
}

// ============================================================================
// Tests
// ============================================================================

test {
    const std = @import("std");
    std.testing.refAllDecls(@This());
}
