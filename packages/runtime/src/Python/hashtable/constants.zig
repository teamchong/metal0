/// Hash table constants
/// Mirrors cpython/Python/hashtable.c configuration

/// Initial hash table size (must be power of 2)
pub const INITIAL_SIZE: usize = 16;

/// Maximum load factor before resize (75%)
pub const MAX_LOAD_FACTOR: f64 = 0.75;

/// Minimum load factor before shrink (25%)
pub const MIN_LOAD_FACTOR: f64 = 0.25;

/// Minimum size to shrink to
pub const MIN_SIZE: usize = 16;
