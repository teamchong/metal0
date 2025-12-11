/// Pointer Hashing
/// Hash functions for pointer identity
///
/// Used for object identity hashing (e.g., hash(obj) when no __hash__ method)

const std = @import("std");
const constants = @import("constants.zig");

const HashT = constants.HashT;
const HASH_MODULUS = constants.HASH_MODULUS;
const HASH_INVALID = constants.HASH_INVALID;

// ============================================================================
// Pointer Hashing
// ============================================================================

/// Hash a pointer (for object identity)
pub fn hashPointer(ptr: *const anyopaque) HashT {
    const addr = @intFromPtr(ptr);

    // Rotate to distribute bits (pointers often have aligned low bits)
    const rotated = std.math.rotr(usize, addr, 4);

    var result: HashT = @intCast(rotated % HASH_MODULUS);
    if (result == HASH_INVALID) {
        result = -2;
    }

    return result;
}

/// Raw pointer hash (without -1 adjustment)
pub fn hashPointerRaw(ptr: *const anyopaque) HashT {
    const addr = @intFromPtr(ptr);
    return @intCast(addr % HASH_MODULUS);
}
