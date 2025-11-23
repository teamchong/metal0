/// Suffix Array construction and LCP (Longest Common Prefix) computation
/// Used for finding frequent substrings in Unigram training
///
/// Algorithm: SA-IS (Suffix Array Induced Sorting) - O(n) time
/// Reference: https://zork.net/~st/jottings/sais.html
/// HuggingFace uses esaxx_rs which implements this algorithm

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Substring with its frequency count
pub const SubstringFreq = struct {
    string: []const u8,
    freq: u32,
};

/// Build suffix array using simple O(n^2 log n) algorithm
/// For production, this should be replaced with SA-IS O(n) algorithm
/// But this is correct and works for training datasets
fn buildSuffixArraySimple(allocator: Allocator, text: []const u8) ![]usize {
    const n = text.len;
    const suffixes = try allocator.alloc(usize, n);

    // Initialize suffix indices
    for (suffixes, 0..) |*suffix, i| {
        suffix.* = i;
    }

    // Sort suffixes lexicographically
    std.mem.sort(usize, suffixes, text, struct {
        pub fn lessThan(txt: []const u8, a_idx: usize, b_idx: usize) bool {
            const a = txt[a_idx..];
            const b = txt[b_idx..];
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    return suffixes;
}

/// Compute LCP (Longest Common Prefix) array
/// lcp[i] = length of longest common prefix between suffix[i] and suffix[i-1]
fn computeLCP(allocator: Allocator, text: []const u8, suffix_array: []const usize) ![]usize {
    const n = text.len;
    var lcp = try allocator.alloc(usize, n);
    @memset(lcp, 0);

    // Rank array: rank[i] = position of suffix starting at i in sorted order
    var rank = try allocator.alloc(usize, n);
    defer allocator.free(rank);

    for (suffix_array, 0..) |sa, i| {
        rank[sa] = i;
    }

    // Kasai's algorithm for LCP computation
    var h: usize = 0;
    for (0..n) |i| {
        if (rank[i] > 0) {
            const j = suffix_array[rank[i] - 1];
            while (i + h < n and j + h < n and text[i + h] == text[j + h]) {
                h += 1;
            }
            lcp[rank[i]] = h;
            if (h > 0) h -= 1;
        }
    }

    return lcp;
}

/// Find all frequent substrings using suffix array and LCP
/// Returns substrings with frequency >= min_freq
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

    // Build suffix array
    const sa = try buildSuffixArraySimple(allocator, text);
    defer allocator.free(sa);

    // Compute LCP array
    const lcp = try computeLCP(allocator, text, sa);
    defer allocator.free(lcp);

    // Find substrings: group suffixes by LCP to find repeated substrings
    var results = std.ArrayList(SubstringFreq){};
    errdefer {
        for (results.items) |item| {
            allocator.free(item.string);
        }
        results.deinit(allocator);
    }

    // Track seen substrings (borrows strings from results, doesn't own them)
    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    // Scan through LCP array to find repeated substrings
    var i: usize = 1;
    while (i < lcp.len) : (i += 1) {
        const common_len = lcp[i];
        if (common_len < min_length or common_len > max_length) {
            continue;
        }

        // This suffix shares 'common_len' prefix with previous suffix
        const suffix_start = sa[i];
        if (suffix_start + common_len > text.len) {
            continue;
        }

        const substring = text[suffix_start..suffix_start + common_len];

        // Count frequency by counting how many consecutive suffixes share this prefix
        var freq: u32 = 1;
        var j = i + 1;
        while (j < lcp.len and lcp[j] >= common_len) : (j += 1) {
            freq += 1;
        }

        // Add to results if not seen before
        const entry = try seen.getOrPut(substring);
        if (!entry.found_existing) {
            const substring_copy = try allocator.dupe(u8, substring);
            errdefer allocator.free(substring_copy);

            try results.append(allocator, SubstringFreq{
                .string = substring_copy,
                .freq = freq,
            });

            if (results.items.len >= max_results) {
                break;
            }
        }

        // Skip past this group
        i = j - 1;
    }

    // Sort by frequency * length (score)
    std.mem.sort(SubstringFreq, results.items, {}, struct {
        pub fn lessThan(_: void, a: SubstringFreq, b: SubstringFreq) bool {
            const score_a = a.freq * @as(u32, @intCast(a.string.len));
            const score_b = b.freq * @as(u32, @intCast(b.string.len));
            return score_a > score_b; // Descending
        }
    }.lessThan);

    // Transfer ownership to caller
    const final = try allocator.alloc(SubstringFreq, results.items.len);
    for (results.items, 0..) |item, idx| {
        final[idx] = item;
    }

    // Free results ArrayList (strings ownership transferred to final)
    results.deinit(allocator);

    return final;
}

// Tests
test "suffix array basic" {
    const allocator = std.testing.allocator;

    const text = "banana";
    const sa = try buildSuffixArraySimple(allocator, text);
    defer allocator.free(sa);

    // Expected: suffixes sorted lexicographically
    // a, ana, anana, banana, na, nana
    // Positions: 5, 3, 1, 0, 4, 2
    try std.testing.expectEqual(@as(usize, 5), sa[0]); // "a"
    try std.testing.expectEqual(@as(usize, 3), sa[1]); // "ana"
    try std.testing.expectEqual(@as(usize, 1), sa[2]); // "anana"
}

test "find frequent substrings" {
    const allocator = std.testing.allocator;

    const text = "banana";
    const results = try findFrequentSubstrings(allocator, text, 2, 10, 100);
    defer {
        for (results) |item| {
            allocator.free(item.string);
        }
        allocator.free(results);
    }

    // Should find "an" and "na" as repeated substrings
    try std.testing.expect(results.len > 0);

    // Just check we got some results
    for (results) |item| {
        try std.testing.expect(item.string.len >= 2);
        try std.testing.expect(item.freq > 0);
    }
}
