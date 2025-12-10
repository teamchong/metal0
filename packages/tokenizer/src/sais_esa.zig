//! SA-IS (Suffix Array Induced Sorting) + ESA (Enhanced Suffix Array)
//! Ported from esaxx-rs (Rust implementation)
//! https://github.com/Narsil/esaxx-rs
//!
//! This provides O(n) linear-time suffix array construction and frequent substring extraction.
//!
//! The full implementation is in sais.zig - this module re-exports the public API.

const std = @import("std");
const Allocator = std.mem.Allocator;
const sais = @import("sais.zig");

// Re-export types and functions from sais.zig
pub const SubstringFreq = sais.SubstringFreq;

/// Find frequent substrings using SA-IS + ESA algorithm
/// O(n) time complexity for suffix array construction
///
/// Arguments:
/// - allocator: Memory allocator for results
/// - text: Input text to analyze
/// - min_length: Minimum substring length to consider
/// - max_length: Maximum substring length (currently unused)
/// - max_results: Maximum number of results to return
///
/// Returns: Array of SubstringFreq sorted by frequency (descending)
pub fn findFrequentSubstrings(
    allocator: Allocator,
    text: []const u8,
    min_length: usize,
    max_length: usize,
    max_results: usize,
) ![]SubstringFreq {
    return sais.findFrequentSubstrings(allocator, text, min_length, max_length, max_results);
}

/// Build suffix array using SA-IS algorithm
/// O(n) time and space complexity
pub fn buildSuffixArray(
    allocator: Allocator,
    text: []const u8,
) ![]usize {
    if (text.len == 0) {
        return try allocator.alloc(usize, 0);
    }

    const n = text.len;

    // Convert text to u32 array
    var string_u32 = try allocator.alloc(u32, n);
    defer allocator.free(string_u32);
    for (text, 0..) |ch, i| {
        string_u32[i] = ch;
    }

    // Allocate suffix array
    const sa = try allocator.alloc(usize, n);
    errdefer allocator.free(sa);

    // Build using SA-IS
    const alphabet_size = 256;
    try sais.saisxx(allocator, string_u32, sa, n, alphabet_size);

    return sa;
}

/// Build Enhanced Suffix Array (SA + LCP information)
/// Returns: (suffix_array, left, right, depth, node_count)
pub fn buildESA(
    allocator: Allocator,
    text: []const u8,
) !struct { sa: []usize, left: []usize, right: []usize, depth: []usize, node_count: usize } {
    if (text.len == 0) {
        return .{
            .sa = try allocator.alloc(usize, 0),
            .left = try allocator.alloc(usize, 0),
            .right = try allocator.alloc(usize, 0),
            .depth = try allocator.alloc(usize, 0),
            .node_count = 0,
        };
    }

    const n = text.len;

    // Convert text to u32 array
    var string_u32 = try allocator.alloc(u32, n);
    defer allocator.free(string_u32);
    for (text, 0..) |ch, i| {
        string_u32[i] = ch;
    }

    // Allocate ESA arrays
    const sa = try allocator.alloc(usize, n);
    errdefer allocator.free(sa);
    const left = try allocator.alloc(usize, n);
    errdefer allocator.free(left);
    const right = try allocator.alloc(usize, n);
    errdefer allocator.free(right);
    const depth = try allocator.alloc(usize, n);
    errdefer allocator.free(depth);

    // Build ESA
    const alphabet_size = 256;
    const node_count = try sais.esaxx(allocator, string_u32, sa, left, right, depth, alphabet_size);

    return .{
        .sa = sa,
        .left = left,
        .right = right,
        .depth = depth,
        .node_count = node_count,
    };
}
