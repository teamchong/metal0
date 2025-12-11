/// Convenience type aliases for common hash table uses
/// Provides pre-configured hash tables for common key types

const hash_table = @import("hash_table.zig");

/// String to value hash table
pub fn StringHashTable(comptime V: type) type {
    return hash_table.HashTable([]const u8, V);
}

/// Pointer to value hash table
pub fn PtrHashTable(comptime V: type) type {
    return hash_table.HashTable(*anyopaque, V);
}

/// Integer to value hash table
pub fn IntHashTable(comptime V: type) type {
    return hash_table.HashTable(u64, V);
}
