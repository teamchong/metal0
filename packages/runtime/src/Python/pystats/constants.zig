/// Constants for pystats module
/// Mirrors cpython/Python/pystats.c

/// Maximum number of opcodes to track
pub const MAX_OPCODES: usize = 256;

/// Maximum call depth for profiling
pub const MAX_CALL_DEPTH: usize = 100;

/// Number of type specialization entries
pub const SPECIALIZATION_ENTRIES: usize = 64;
