//! SA-IS (Suffix Array Induced Sorting) - O(n) linear time
//! Ported from esaxx-rs: https://github.com/Narsil/esaxx-rs
//! Original implementation in Rust (sais.rs)

const std = @import("std");
const Allocator = std.mem.Allocator;

// Type aliases matching Rust implementation
// StringT = [u32] - text as u32 codepoints
// SArray = [usize] - suffix array indices
// Bucket = [usize] - character buckets

const MAX_ALPHABET_SIZE = 0x110000; // Full Unicode range

fn hasHighBit(j: usize) bool {
    return (0x0001 & @bitReverse(j)) == 1;
}

fn getCounts(t: []const u32, c: []usize) void {
    @memset(c, 0);
    for (t) |ch| {
        c[ch] += 1;
    }
}

fn getBuckets(c: []const usize, b: []usize, end: bool) void {
    var sum: usize = 0;
    if (end) {
        for (c, 0..) |count, i| {
            sum += count;
            b[i] = sum;
        }
    } else {
        for (c, 0..) |count, i| {
            b[i] = sum;
            sum += count;
        }
    }
}

fn induceSA(
    string: []const u32,
    suffix_array: []usize,
    counts: []usize,
    buckets: []usize,
    n: usize,
) void {
    std.debug.assert(n <= suffix_array.len);
    getCounts(string, counts);
    getBuckets(counts, buckets, false);

    var c0: usize = undefined;
    var j = n - 1;
    var c1: usize = string[j];
    var index = buckets[c1];
    suffix_array[index] = if (j > 0 and string[j - 1] < c1) ~j else j;
    index += 1;
    
    for (0..n) |i| {
        j = suffix_array[i];
        suffix_array[i] = ~j;
        if (!hasHighBit(j) and j > 0) {
            j -= 1;
            c0 = string[j];
            if (c0 != c1) {
                buckets[c1] = index;
                c1 = c0;
                index = buckets[c1];
            }
            suffix_array[index] = if (j > 0 and !hasHighBit(j) and string[j - 1] < c1) ~j else j;
            index += 1;
        }
    }
    
    // Compute SA - second pass
    getCounts(string, counts);
    getBuckets(counts, buckets, true);
    c1 = 0;
    index = buckets[c1];
    
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        j = suffix_array[i];
        if (j > 0 and !hasHighBit(j)) {
            j -= 1;
            c0 = string[j];
            if (c0 != c1) {
                buckets[c1] = index;
                c1 = c0;
                index = buckets[c1];
            }
            index -= 1;
            suffix_array[index] = if (j == 0 or string[j - 1] > c1) ~j else j;
        } else {
            suffix_array[i] = ~j;
        }
    }
}

fn suffixsort(
    allocator: Allocator,
    string: []const u32,
    suffix_array: []usize,
    fs: usize,
    n: usize,
    k: usize,
    is_bwt: bool,
) !usize {
    const pidx: usize = 0;
    var c0: usize = undefined;

    const counts = try allocator.alloc(usize, k);
    defer allocator.free(counts);
    const buckets = try allocator.alloc(usize, k);
    defer allocator.free(buckets);

    getCounts(string, counts);
    getBuckets(counts, buckets, true);

    // Stage 1: Sort all S-substrings
    @memset(suffix_array, 0);
    var c_index: usize = 0;
    var c1: usize = string[n - 1];

    var i: usize = n - 1;
    while (i > 0) {
        i -= 1;
        c0 = string[i];
        if (c0 < c1 + c_index) {
            c_index = 1;
        } else if (c_index != 0) {
            buckets[c1] -= 1;
            suffix_array[buckets[c1]] = i + 1;
            c_index = 0;
        }
        c1 = c0;
    }

    induceSA(string, suffix_array, counts, buckets, n);

    // Compact all sorted substrings
    var p: usize = undefined;
    var j: usize = undefined;
    var m: usize = 0;

    for (0..n) |idx| {
        p = suffix_array[idx];
        c0 = string[p];
        if (p > 0 and string[p - 1] > c0) {
            j = p + 1;
            if (j < n) {
                c1 = string[j];
            }
            while (j < n and c0 == c1) {
                c1 = string[j];
                j += 1;
            }
            if (j < n and c0 < c1) {
                suffix_array[m] = p;
                m += 1;
            }
        }
    }

    j = m + (n >> 1);
    for (m..j) |idx| {
        suffix_array[idx] = 0;
    }

    // Store length of all substrings
    j = n;
    c_index = 0;
    c1 = string[n - 1];

    i = n - 1;
    while (i > 0) {
        i -= 1;
        c0 = string[i];
        if (c0 < c1 + c_index) {
            c_index = 1;
        } else if (c_index != 0) {
            suffix_array[m + ((i + 1) >> 1)] = j - i - 1;
            j = i + 1;
            c_index = 0;
        }
        c1 = c0;
    }

    // Find lexicographic names
    var name: usize = 0;
    var q: usize = n;
    var qlen: usize = 0;
    var plen: usize = undefined;
    var diff: bool = undefined;

    for (0..m) |idx| {
        p = suffix_array[idx];
        plen = suffix_array[m + (p >> 1)];
        diff = true;
        if (plen == qlen) {
            j = 0;
            while (j < plen and string[p + j] == string[q + j]) {
                j += 1;
            }
            if (j == plen) {
                diff = false;
            }
        }
        if (diff) {
            name += 1;
            q = p;
            qlen = plen;
        }
        suffix_array[m + (p >> 1)] = name;
    }

    // Stage 2: Recurse if names not unique
    if (name < m) {
        const ra_index = n + fs - m;
        j = m - 1;
        const a = m + (n >> 1);

        i = a;
        while (i > m) {
            i -= 1;
            if (suffix_array[i] != 0) {
                suffix_array[ra_index + j] = suffix_array[i] - 1;
                j = if (j > 0) j - 1 else 0;
            }
        }

        // Build reduced string
        var ra = try allocator.alloc(u32, m);
        defer allocator.free(ra);
        for (0..m) |idx| {
            ra[idx] = @intCast(suffix_array[ra_index + idx]);
        }

        _ = try suffixsort(allocator, ra, suffix_array, fs + n - m * 2, m, name, false);

        j = m - 1;
        c_index = 0;
        c1 = string[n - 1];

        i = n - 1;
        while (i > 0) {
            i -= 1;
            c0 = string[i];
            if (c0 < c1 + c_index) {
                c_index = 1;
            } else if (c_index != 0) {
                suffix_array[ra_index + j] = i + 1;
                c_index = 0;
                j = if (j > 0) j - 1 else 0;
            }
            c1 = c0;
        }

        // Get index in s
        for (0..m) |idx| {
            suffix_array[idx] = suffix_array[ra_index + suffix_array[idx]];
        }
    }

    // Stage 3: Induce result
    getCounts(string, counts);
    getBuckets(counts, buckets, true);

    for (m..n) |idx| {
        suffix_array[idx] = 0;
    }

    i = m;
    while (i > 0) {
        i -= 1;
        j = suffix_array[i];
        suffix_array[i] = 0;
        if (buckets[string[j]] > 0) {
            buckets[string[j]] -= 1;
            suffix_array[buckets[string[j]]] = j;
        }
    }

    if (is_bwt) {
        // TODO: compute_bwt if needed
        return error.NotImplemented;
    } else {
        induceSA(string, suffix_array, counts, buckets, n);
    }

    return pidx;
}

pub fn saisxx(
    allocator: Allocator,
    string: []const u32,
    suffix_array: []usize,
    n: usize,
    k: usize,
) !void {
    if (n == 1) {
        suffix_array[0] = 0;
        return;
    }
    const fs = 0;
    _ = try suffixsort(allocator, string, suffix_array, fs, n, k, false);
}

// ESA (Enhanced Suffix Array) implementation
// Ported from esa.rs

pub const SubstringFreq = struct {
    string: []const u8,
    freq: u32,
};

fn suffixTree(
    allocator: Allocator,
    string: []const u32,
    suffix_array: []usize,
    left: []usize,
    right: []usize,
    depth: []usize,
    n: usize,
) usize {
    if (n == 0) return 0;

    // Psi = l
    left[suffix_array[0]] = suffix_array[n - 1];
    for (1..n) |i| {
        left[suffix_array[i]] = suffix_array[i - 1];
    }

    // PLCP = r
    var h: usize = 0;
    for (0..n) |i| {
        const j = left[i];
        while (i + h < n and j + h < n and string[i + h] == string[j + h]) {
            h += 1;
        }
        right[i] = h;
        if (h > 0) h -= 1;
    }

    // H = l
    for (0..n) |i| {
        left[i] = right[suffix_array[i]];
    }

    var stack = std.ArrayList(struct { i32, i32 }){};
    defer stack.deinit(allocator);
    stack.append(allocator, .{ -1, -1 }) catch unreachable;

    var node_num: usize = 0;
    var i: usize = 0;

    while (true) {
        var cur: struct { i32, i32 } = .{ @intCast(i), if (i == n) -1 else @as(i32, @intCast(left[i])) };
        var cand = stack.items[stack.items.len - 1];

        while (cand[1] > cur[1]) {
            if (i - @as(usize, @intCast(cand[0])) > 1) {
                left[node_num] = @intCast(cand[0]);
                right[node_num] = i;
                depth[node_num] = @intCast(cand[1]);
                node_num += 1;
                if (node_num >= n) break;
            }
            cur[0] = cand[0];
            _ = stack.pop();
            cand = stack.items[stack.items.len - 1];
        }

        if (cand[1] < cur[1]) {
            stack.append(allocator, cur) catch unreachable;
        }

        if (i == n) break;

        stack.append(allocator, .{ @intCast(i), @as(i32, @intCast(n - suffix_array[i] + 1)) }) catch unreachable;
        i += 1;
    }

    return node_num;
}

pub fn esaxx(
    allocator: Allocator,
    string: []const u32,
    suffix_array: []usize,
    left: []usize,
    right: []usize,
    depth: []usize,
    k: usize,
) !usize {
    const n = string.len;
    try saisxx(allocator, string, suffix_array, n, k);
    const node_num = suffixTree(allocator, string, suffix_array, left, right, depth, n);
    return node_num;
}

/// Main API: Find frequent substrings using SA-IS + ESA
pub fn findFrequentSubstrings(
    allocator: Allocator,
    text: []const u8,
    min_length: usize,
    _: usize, // max_length unused for now
    max_results: usize,
) ![]SubstringFreq {
    if (text.len == 0) {
        return try allocator.alloc(SubstringFreq, 0);
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
    defer allocator.free(sa);
    const left = try allocator.alloc(usize, n);
    defer allocator.free(left);
    const right = try allocator.alloc(usize, n);
    defer allocator.free(right);
    const depth = try allocator.alloc(usize, n);
    defer allocator.free(depth);

    // Build ESA
    const alphabet_size = 256; // Byte alphabet
    const node_num = try esaxx(allocator, string_u32, sa, left, right, depth, alphabet_size);
    // Analyze depth distribution
    var depth_hist = [_]usize{0} ** 10; // 0, 1, 2-5, 6-10, 11-20, 21-50, 51-100, 101-200, 201+
    for (0..node_num) |i| {
        const d = depth[i];
        if (d == 0) depth_hist[0] += 1
        else if (d == 1) depth_hist[1] += 1
        else if (d <= 5) depth_hist[2] += 1
        else if (d <= 10) depth_hist[3] += 1
        else if (d <= 20) depth_hist[4] += 1
        else if (d <= 50) depth_hist[5] += 1
        else if (d <= 100) depth_hist[6] += 1
        else if (d <= 200) depth_hist[7] += 1
        else depth_hist[8] += 1;
    }
    std.debug.print("[SA DEBUG] ESA node_num: {d}, text_len: {d}\n", .{node_num, n});
    std.debug.print("[SA DEBUG] Depth dist: 0={d}, 1={d}, 2-5={d}, 6-10={d}, 11-20={d}, 21-50={d}, 51-100={d}, 101-200={d}, 201+={d}\n",
        .{depth_hist[0], depth_hist[1], depth_hist[2], depth_hist[3], depth_hist[4], depth_hist[5], depth_hist[6], depth_hist[7], depth_hist[8]});

    // Extract frequent substrings from ESA nodes
    // Match esaxx behavior: ONE substring per node at depth[i] length
    var results = std.ArrayList(SubstringFreq){};
    errdefer {
        for (results.items) |item| allocator.free(item.string);
        results.deinit(allocator);
    }

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var filtered_len: usize = 0;
    var filtered_offset: usize = 0;
    const filtered_null: usize = 0; // Not filtering nulls in sais.zig anymore
    var filtered_seen: usize = 0;

    for (0..node_num) |i| {
        const len = depth[i];
        // Only filter minimum length (HF filters len <= 1)
        if (len < min_length) {
            filtered_len += 1;
            continue;
        }
        // No max length filter - let scoring handle quality

        const l = left[i];
        const offset = sa[l];
        const freq: u32 = @intCast(right[i] - l);

        if (offset + len > text.len) {
            filtered_offset += 1;
            continue;
        }

        const substring = text[offset..offset + len];

        // NOTE: Don't filter '\0' here - let caller decide
        // HuggingFace's esaxx returns all substrings, filtering happens in trainer
        // if (std.mem.indexOfScalar(u8, substring, 0) != null) {
        //     filtered_null += 1;
        //     continue;
        // }

        const entry = try seen.getOrPut(substring);
        if (!entry.found_existing) {
            const copy = try allocator.dupe(u8, substring);
            errdefer allocator.free(copy);

            try results.append(allocator, SubstringFreq{
                .string = copy,
                .freq = freq,
            });

            if (results.items.len >= max_results) break;
        } else {
            filtered_seen += 1;
        }
    }

    std.debug.print("[SA DEBUG] Filtered: len={d}, offset={d}, null={d}, seen={d}, kept={d}\n",
        .{filtered_len, filtered_offset, filtered_null, filtered_seen, results.items.len});

    // Sort by score
    std.mem.sort(SubstringFreq, results.items, {}, struct {
        pub fn lessThan(_: void, a: SubstringFreq, b: SubstringFreq) bool {
            const score_a = a.freq * @as(u32, @intCast(a.string.len));
            const score_b = b.freq * @as(u32, @intCast(b.string.len));
            return score_a > score_b;
        }
    }.lessThan);

    return try results.toOwnedSlice(allocator);
}
