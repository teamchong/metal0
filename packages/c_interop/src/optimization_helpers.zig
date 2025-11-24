/// Optimization helpers for C interop layer
///
/// Provides optimized allocator selection and hash functions
/// based on proven patterns from tokenizer package

const std = @import("std");
const builtin = @import("builtin");

// Import wyhash from tokenizer package
const wyhash_path = "../../tokenizer/src/wyhash.zig";
const wyhash = @import(wyhash_path);

/// Get optimal allocator for C interop
/// - C extensions expect C allocator behavior
/// - Must use std.heap.c_allocator for CPython compatibility
/// - This is correct and cannot be changed (C extensions rely on it)
pub fn getCInteropAllocator() std.mem.Allocator {
    return std.heap.c_allocator;
}

/// Fast string hash context using wyhash (from Bun, 1.05x faster)
/// Use for PyDict string key hashing
pub const WyhashStringContext = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        return wyhash.WyhashStateless.hash(0, key);
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

/// Type alias for string-keyed HashMap with wyhash
/// Use for PyDict internal implementation
pub fn StringHashMap(comptime V: type) type {
    return std.HashMap([]const u8, V, WyhashStringContext, std.hash_map.default_max_load_percentage);
}

/// Fast hash for PyObject pointers (used in PyDict)
/// Uses identity hash (pointer value) which is correct for Python
pub fn hashPyObject(obj: *const anyopaque) u64 {
    const ptr_val = @intFromPtr(obj);
    return wyhash.WyhashStateless.hash(0, std.mem.asBytes(&ptr_val));
}

/// Fast hash for string data (used when hashing string contents)
pub fn hashString(data: []const u8) u64 {
    return wyhash.WyhashStateless.hash(0, data);
}

test "optimization helpers" {
    const alloc = getCInteropAllocator();
    const mem = try alloc.alloc(u8, 100);
    defer alloc.free(mem);
    
    // Test string hash
    const hash1 = hashString("hello");
    const hash2 = hashString("hello");
    const hash3 = hashString("world");
    
    try std.testing.expectEqual(hash1, hash2);
    try std.testing.expect(hash1 != hash3);
}
