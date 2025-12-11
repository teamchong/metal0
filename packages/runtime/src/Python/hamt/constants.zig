/// Constants for HAMT implementation
/// Mirrors cpython/Python/hamt.c

/// Bits per level of the trie
pub const BITS_PER_LEVEL: u5 = 5;

/// Number of children per full node (2^5 = 32)
pub const BRANCH_FACTOR: usize = 1 << BITS_PER_LEVEL;

/// Mask for extracting bits at each level
pub const LEVEL_MASK: u32 = BRANCH_FACTOR - 1;

/// Maximum depth of the trie
pub const MAX_DEPTH: usize = 7; // 32 bits / 5 bits per level + collision level

/// Threshold for switching from bitmap to array node
pub const BITMAP_TO_ARRAY_THRESHOLD: usize = 16;
