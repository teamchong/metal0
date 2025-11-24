//! Simplified SA-IS-inspired suffix array construction
//! Goal: Better than O(n² log n), good enough for tokenizer
//! 
//! Strategy: Use a hybrid approach:
//! 1. Use simple O(n log n) per-character sorting (faster than O(n² log n))
//! 2. Improve LCP calculation with better grouping
//! 3. Extract more frequent substrings with better heuristics

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SubstringFreq = struct {
    string: []const u8,
    freq: u32,
};

/// Build suffix array using O(n log² n) approach
/// Better than our O(n² log n) but simpler than full SA-IS O(n)
fn buildSuffixArray(allocator: Allocator, text: []const u8) ![]usize {
    const n = text.len;
    var sa = try allocator.alloc(usize, n);
    
    // Initialize with indices
    for (sa, 0..) |*s, i| {
        s.* = i;
    }
    
    // Sort using std.mem.sort (O(n log n) with good comparisons)
    std.mem.sort(usize, sa, text, struct {
        pub fn lessThan(t: []const u8, a_idx: usize, b_idx: usize) bool {
            const a = t[a_idx..];
            const b = t[b_idx..];
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    
    return sa;
}

/// Compute LCP array using Kasai's algorithm O(n)
fn computeLCP(allocator: Allocator, text: []const u8, sa: []const usize) ![]usize {
    const n = text.len;
    var lcp = try allocator.alloc(usize, n);
    var rank = try allocator.alloc(usize, n);
    defer allocator.free(rank);
    
    // Compute rank array (inverse of SA)
    for (sa, 0..) |pos, i| {
        rank[pos] = i;
    }
    
    var h: usize = 0;
    for (0..n) |i| {
        if (rank[i] > 0) {
            const j = sa[rank[i] - 1];
            while (i + h < n and j + h < n and text[i + h] == text[j + h]) {
                h += 1;
            }
            lcp[rank[i]] = h;
            if (h > 0) h -= 1;
        }
    }
    
    return lcp;
}

/// Find frequent substrings - improved version with better extraction
pub fn findFrequentSubstrings(
    allocator: Allocator,
    text: []const u8,
    min_length: usize,
    max_length: usize,
    max_results: usize,
) ![]SubstringFreq {
    if (text.len == 0) {
        return try allocator.alloc(SubstringFreq, 0);
    }
    
    // Build suffix array (O(n log² n))
    const sa = try buildSuffixArray(allocator, text);
    defer allocator.free(sa);
    
    // Compute LCP array (O(n))
    const lcp = try computeLCP(allocator, text, sa);
    defer allocator.free(lcp);
    
    var results = std.ArrayList(SubstringFreq){};
    errdefer {
        for (results.items) |item| allocator.free(item.string);
        results.deinit(allocator);
    }
    
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    
    // Extract frequent substrings with ALL lengths (like before)
    var i: usize = 1;
    while (i < lcp.len) : (i += 1) {
        const common_len = lcp[i];
        if (common_len < min_length) continue;
        
        const suffix_start = sa[i];
        
        // Count frequency
        var freq: u32 = 1;
        var j = i + 1;
        while (j < lcp.len and lcp[j] >= common_len) : (j += 1) {
            freq += 1;
        }
        
        // Extract ALL lengths from min_length to common_len
        const max_extract = @min(common_len, max_length);
        var len = min_length;
        while (len <= max_extract) : (len += 1) {
            if (suffix_start + len > text.len) continue;
            
            const substring = text[suffix_start..suffix_start + len];
            
            const entry = try seen.getOrPut(substring);
            if (!entry.found_existing) {
                const copy = try allocator.dupe(u8, substring);
                errdefer allocator.free(copy);
                
                try results.append(allocator, SubstringFreq{
                    .string = copy,
                    .freq = freq,
                });
                
                if (results.items.len >= max_results) break;
            }
        }
        
        if (results.items.len >= max_results) break;
        i = j - 1;
    }
    
    // Sort by score (freq * length)
    std.mem.sort(SubstringFreq, results.items, {}, struct {
        pub fn lessThan(_: void, a: SubstringFreq, b: SubstringFreq) bool {
            const score_a = a.freq * @as(u32, @intCast(a.string.len));
            const score_b = b.freq * @as(u32, @intCast(b.string.len));
            return score_a > score_b;
        }
    }.lessThan);
    
    return try results.toOwnedSlice(allocator);
}
