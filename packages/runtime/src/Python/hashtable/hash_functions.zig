/// Hash functions for different key types
/// Mirrors cpython/Python/hashtable.c hash implementations

/// FNV-1a hash for bytes
pub fn fnvHash(data: []const u8) u64 {
    const FNV_OFFSET: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;

    var hash: u64 = FNV_OFFSET;
    for (data) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }
    return hash;
}

/// Hash for pointers
pub fn ptrHash(ptr: ?*const anyopaque) u64 {
    const addr = @intFromPtr(ptr);
    // Mix bits
    var h = addr;
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    h *%= 0xc4ceb9fe1a85ec53;
    h ^= h >> 33;
    return h;
}

/// Identity hash (for pre-hashed values)
pub fn identityHash(value: u64) u64 {
    return value;
}
