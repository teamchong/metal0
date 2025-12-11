/// hashtable - Generic Hash Table Implementation
/// Mirrors cpython/Python/hashtable.c
///
/// This module provides a generic hash table with:
/// - Configurable hash and compare functions
/// - Automatic resizing
/// - Iterator support
/// - Statistics tracking

// Re-export constants
pub const INITIAL_SIZE = @import("hashtable/constants.zig").INITIAL_SIZE;
pub const MAX_LOAD_FACTOR = @import("hashtable/constants.zig").MAX_LOAD_FACTOR;
pub const MIN_LOAD_FACTOR = @import("hashtable/constants.zig").MIN_LOAD_FACTOR;
pub const MIN_SIZE = @import("hashtable/constants.zig").MIN_SIZE;

// Re-export hash functions
pub const fnvHash = @import("hashtable/hash_functions.zig").fnvHash;
pub const ptrHash = @import("hashtable/hash_functions.zig").ptrHash;
pub const identityHash = @import("hashtable/hash_functions.zig").identityHash;

// Re-export core type
pub const HashTable = @import("hashtable/hash_table.zig").HashTable;

// Re-export convenience types
pub const StringHashTable = @import("hashtable/convenience_types.zig").StringHashTable;
pub const PtrHashTable = @import("hashtable/convenience_types.zig").PtrHashTable;
pub const IntHashTable = @import("hashtable/convenience_types.zig").IntHashTable;

// Re-export set implementation
pub const HashSet = @import("hashtable/hash_set.zig").HashSet;

// Initialization function
pub fn init() void {}

// Re-export tests
test {
    @import("std").testing.refAllDecls(@import("hashtable/tests.zig"));
}
