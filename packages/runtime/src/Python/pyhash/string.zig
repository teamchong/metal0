/// String/Bytes Hashing
/// Hash functions for string and bytes objects
///
/// Uses SipHash-2-4 for cryptographically strong hashing.

const std = @import("std");
const constants = @import("constants.zig");
const siphash = @import("siphash.zig");

const HashT = constants.HashT;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INVALID = constants.HASH_INVALID;

// ============================================================================
// String/Bytes Hashing
// ============================================================================

/// Hash a byte buffer (Python's Py_HashBuffer equivalent)
pub fn hashBuffer(data: []const u8) HashT {
    if (data.len == 0) {
        return 0;
    }

    const h = siphash.sipHash24(data);

    // Convert to signed and handle -1 case
    var result: HashT = @bitCast(h & HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }
    return result;
}

/// Hash a string (same as hashBuffer for UTF-8)
pub fn hashString(s: []const u8) HashT {
    return hashBuffer(s);
}

// ============================================================================
// Tests
// ============================================================================

test "hash string" {
    const secret = @import("secret.zig");
    secret.initHashSecret();

    const h1 = hashString("hello");
    const h2 = hashString("hello");
    const h3 = hashString("world");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}
