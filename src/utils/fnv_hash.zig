const std = @import("std");

/// Standalone FNV-1a hash for string keys (comptime and runtime)
pub fn hash(key: []const u8) u64 {
    const FNV_OFFSET: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;

    var h: u64 = FNV_OFFSET;
    for (key) |byte| {
        h ^= byte;
        h *%= FNV_PRIME;
    }
    return h;
}

/// FNV-1a hash context for HashMap
/// Optimized for small keys (u32, pairs of u32) and string keys
pub fn FnvHashContext(comptime K: type) type {
    const is_string = K == []const u8;

    return struct {
        pub fn hash(_: @This(), key: K) u64 {
            const FNV_OFFSET: u64 = 0xcbf29ce484222325;
            const FNV_PRIME: u64 = 0x100000001b3;

            var h: u64 = FNV_OFFSET;

            if (is_string) {
                // Optimized path for string keys (vocab lookups)
                // Unroll for common small strings (≤8 bytes)
                if (key.len <= 8) {
                    // Unrolled loop for better performance on short strings
                    var i: usize = 0;
                    while (i < key.len) : (i += 1) {
                        h ^= key[i];
                        h *%= FNV_PRIME;
                    }
                } else {
                    // Standard loop for longer strings
                    for (key) |byte| {
                        h ^= byte;
                        h *%= FNV_PRIME;
                    }
                }
            } else {
                // Generic path for fixed-size keys (u32, pairs, etc.)
                const bytes = std.mem.asBytes(&key);
                for (bytes) |byte| {
                    h ^= byte;
                    h *%= FNV_PRIME;
                }
            }

            return h;
        }

        pub fn eql(_: @This(), a: K, b: K) bool {
            if (is_string) {
                return std.mem.eql(u8, a, b);
            } else {
                return std.mem.eql(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
            }
        }
    };
}
