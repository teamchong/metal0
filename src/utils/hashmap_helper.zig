/// Optimized HashMap utilities for PyAOT
/// ALWAYS use these instead of std.StringHashMap for performance!
///
/// Performance: wyhash is 1.05x faster than default hash (same as Bun)
/// Used by: PyDict, tokenizer vocab lookups, any string-keyed hashmaps
const std = @import("std");
const wyhash = @import("wyhash.zig");

/// Fast string hash context using wyhash (same as Bun)
pub const WyhashStringContext = struct {
    pub fn hash(_: @This(), key: []const u8) u64 {
        return wyhash.WyhashStateless.hash(0, key);
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

/// Fast string-keyed HashMap with wyhash
/// Use this instead of std.StringHashMap!
///
/// Example:
///   var map = hashmap_helper.StringHashMap(ValueType).init(allocator);
pub fn StringHashMap(comptime V: type) type {
    return std.HashMap([]const u8, V, WyhashStringContext, std.hash_map.default_max_load_percentage);
}
