/// suggestions - Error Suggestions ("Did you mean?")
/// Mirrors cpython/Python/suggestions.c
///
/// This module provides "Did you mean X?" suggestions for error messages:
/// - Levenshtein distance calculation
/// - Attribute name suggestions
/// - Variable name suggestions
/// - Import name suggestions

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Maximum candidates to consider
pub const MAX_CANDIDATE_ITEMS: usize = 750;

/// Maximum string length to compare
pub const MAX_STRING_SIZE: usize = 40;

/// Cost of moving a character
pub const MOVE_COST: usize = 2;

/// Cost of case change
pub const CASE_COST: usize = 1;

/// Default threshold for "close enough" suggestion
pub const DEFAULT_THRESHOLD: usize = 4;

// ============================================================================
// Edit Distance
// ============================================================================

/// Calculate substitution cost between two characters
fn substitutionCost(a: u8, b: u8) usize {
    // Quick check: same least 5 bits means possibly same letter
    if ((a & 31) != (b & 31)) {
        return MOVE_COST;
    }

    if (a == b) {
        return 0;
    }

    // Check for case flip
    const a_lower = if (a >= 'A' and a <= 'Z') a + 32 else a;
    const b_lower = if (b >= 'A' and b <= 'Z') b + 32 else b;

    if (a_lower == b_lower) {
        return CASE_COST;
    }

    return MOVE_COST;
}

/// Calculate Levenshtein distance between two strings
/// Returns distance or max_cost + 1 if too far
pub fn levenshteinDistance(a: []const u8, b: []const u8, max_cost: usize) usize {
    // Same string by identity
    if (a.ptr == b.ptr and a.len == b.len) {
        return 0;
    }

    var a_start: usize = 0;
    var b_start: usize = 0;
    var a_len = a.len;
    var b_len = b.len;

    // Trim common prefix
    while (a_len > 0 and b_len > 0 and a[a_start] == b[b_start]) {
        a_start += 1;
        b_start += 1;
        a_len -= 1;
        b_len -= 1;
    }

    // Trim common suffix
    while (a_len > 0 and b_len > 0 and a[a_start + a_len - 1] == b[b_start + b_len - 1]) {
        a_len -= 1;
        b_len -= 1;
    }

    // One string is substring of other
    if (a_len == 0 or b_len == 0) {
        return (a_len + b_len) * MOVE_COST;
    }

    // Too long
    if (a_len > MAX_STRING_SIZE or b_len > MAX_STRING_SIZE) {
        return max_cost + 1;
    }

    // Make a the shorter one
    var str_a = a[a_start .. a_start + a_len];
    var str_b = b[b_start .. b_start + b_len];
    var len_a = a_len;
    var len_b = b_len;

    if (b_len < a_len) {
        const tmp_str = str_a;
        str_a = str_b;
        str_b = tmp_str;
        const tmp_len = len_a;
        len_a = len_b;
        len_b = tmp_len;
    }

    // Quick fail: length difference alone exceeds max
    if ((len_b - len_a) * MOVE_COST > max_cost) {
        return max_cost + 1;
    }

    // Single row DP buffer
    var buffer: [MAX_STRING_SIZE]usize = undefined;

    // Initialize first row
    var tmp: usize = MOVE_COST;
    for (0..len_a) |i| {
        buffer[i] = tmp;
        tmp += MOVE_COST;
    }

    var result: usize = 0;

    // Fill in the DP matrix row by row
    for (0..len_b) |b_index| {
        const code = str_b[b_index];
        var distance: usize = b_index * MOVE_COST;
        result = distance;
        var minimum: usize = std.math.maxInt(usize);

        for (0..len_a) |index| {
            // Substitution cost
            const substitute = distance + substitutionCost(code, str_a[index]);

            // Previous cost from row above
            distance = buffer[index];

            // Insert/delete cost
            const insert_delete = @min(result, distance) + MOVE_COST;

            result = @min(insert_delete, substitute);
            buffer[index] = result;

            if (result < minimum) {
                minimum = result;
            }
        }

        // Early termination if all values too large
        if (minimum > max_cost) {
            return max_cost + 1;
        }
    }

    return result;
}

/// Calculate edit cost between two strings (exported for Python)
pub fn editCost(a: []const u8, b: []const u8) usize {
    return levenshteinDistance(a, b, std.math.maxInt(usize));
}

// ============================================================================
// Suggestion Finding
// ============================================================================

/// Result of suggestion search
pub const Suggestion = struct {
    name: []const u8,
    distance: usize,
};

/// Find closest match in a list of candidates
pub fn findClosestMatch(
    target: []const u8,
    candidates: []const []const u8,
    max_distance: usize,
) ?Suggestion {
    if (candidates.len >= MAX_CANDIDATE_ITEMS) {
        return null;
    }

    if (target.len == 0 or target.len > MAX_STRING_SIZE) {
        return null;
    }

    var best_distance: usize = max_distance + 1;
    var best_match: ?[]const u8 = null;

    for (candidates) |candidate| {
        if (candidate.len == 0 or candidate.len > MAX_STRING_SIZE) {
            continue;
        }

        // Quick length check
        const len_diff = if (target.len > candidate.len)
            target.len - candidate.len
        else
            candidate.len - target.len;

        if (len_diff * MOVE_COST > best_distance) {
            continue;
        }

        const distance = levenshteinDistance(target, candidate, best_distance);

        if (distance < best_distance) {
            best_distance = distance;
            best_match = candidate;
        }
    }

    if (best_match) |match| {
        return .{
            .name = match,
            .distance = best_distance,
        };
    }

    return null;
}

/// Find suggestion with default threshold
pub fn suggest(target: []const u8, candidates: []const []const u8) ?[]const u8 {
    if (findClosestMatch(target, candidates, DEFAULT_THRESHOLD)) |s| {
        return s.name;
    }
    return null;
}

// ============================================================================
// Specific Suggestion Types
// ============================================================================

/// Suggest attribute name
pub fn suggestAttribute(
    name: []const u8,
    attrs: []const []const u8,
) ?[]const u8 {
    // Use stricter threshold for attributes
    const threshold = @max(name.len / 2, 2);
    if (findClosestMatch(name, attrs, threshold)) |s| {
        return s.name;
    }
    return null;
}

/// Suggest variable name from scope
pub fn suggestVariable(
    name: []const u8,
    locals: []const []const u8,
    globals: []const []const u8,
) ?[]const u8 {
    const threshold = @max(name.len / 2, 2);

    // Check locals first
    if (findClosestMatch(name, locals, threshold)) |s| {
        return s.name;
    }

    // Then globals
    if (findClosestMatch(name, globals, threshold)) |s| {
        return s.name;
    }

    return null;
}

/// Suggest import name
pub fn suggestImport(
    name: []const u8,
    available: []const []const u8,
) ?[]const u8 {
    return suggest(name, available);
}

// ============================================================================
// Error Message Formatting
// ============================================================================

/// Format "Did you mean 'X'?" message
pub fn formatSuggestion(
    allocator: Allocator,
    original_name: []const u8,
    suggestion: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "Did you mean '{s}'?",
        .{suggestion},
    );
}

/// Format NameError with suggestion
pub fn formatNameError(
    allocator: Allocator,
    name: []const u8,
    suggestion: ?[]const u8,
) ![]const u8 {
    if (suggestion) |s| {
        return std.fmt.allocPrint(
            allocator,
            "name '{s}' is not defined. Did you mean '{s}'?",
            .{ name, s },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "name '{s}' is not defined",
        .{name},
    );
}

/// Format AttributeError with suggestion
pub fn formatAttributeError(
    allocator: Allocator,
    type_name: []const u8,
    attr_name: []const u8,
    suggestion: ?[]const u8,
) ![]const u8 {
    if (suggestion) |s| {
        return std.fmt.allocPrint(
            allocator,
            "'{s}' object has no attribute '{s}'. Did you mean '{s}'?",
            .{ type_name, attr_name, s },
        );
    }
    return std.fmt.allocPrint(
        allocator,
        "'{s}' object has no attribute '{s}'",
        .{ type_name, attr_name },
    );
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "substitution cost" {
    // Same character
    try std.testing.expectEqual(@as(usize, 0), substitutionCost('a', 'a'));

    // Case flip
    try std.testing.expectEqual(CASE_COST, substitutionCost('a', 'A'));
    try std.testing.expectEqual(CASE_COST, substitutionCost('Z', 'z'));

    // Different characters
    try std.testing.expectEqual(MOVE_COST, substitutionCost('a', 'b'));
    try std.testing.expectEqual(MOVE_COST, substitutionCost('x', 'y'));
}

test "levenshtein distance" {
    // Same string
    try std.testing.expectEqual(@as(usize, 0), levenshteinDistance("hello", "hello", 10));

    // Empty string
    try std.testing.expectEqual(@as(usize, 10), levenshteinDistance("hello", "", 20));

    // One character diff
    try std.testing.expectEqual(MOVE_COST, levenshteinDistance("hello", "hallo", 10));

    // Case difference
    try std.testing.expectEqual(CASE_COST, levenshteinDistance("Hello", "hello", 10));

    // Multiple diffs
    const dist = levenshteinDistance("kitten", "sitting", 20);
    try std.testing.expect(dist > 0);
}

test "find closest match" {
    const candidates = &[_][]const u8{
        "apple",
        "apply",
        "banana",
        "orange",
    };

    // Exact match
    const result1 = findClosestMatch("apple", candidates, 5);
    try std.testing.expect(result1 != null);
    try std.testing.expectEqualStrings("apple", result1.?.name);
    try std.testing.expectEqual(@as(usize, 0), result1.?.distance);

    // Close match
    const result2 = findClosestMatch("appla", candidates, 5);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqualStrings("apple", result2.?.name);

    // No close match
    const result3 = findClosestMatch("xyz", candidates, 2);
    try std.testing.expect(result3 == null);
}

test "suggest" {
    const candidates = &[_][]const u8{
        "print",
        "input",
        "format",
    };

    // Close typo
    const s1 = suggest("pritn", candidates);
    try std.testing.expect(s1 != null);
    try std.testing.expectEqualStrings("print", s1.?);

    // Not close enough
    const s2 = suggest("xyz", candidates);
    try std.testing.expect(s2 == null);
}

test "format suggestion" {
    const allocator = std.testing.allocator;

    const msg = try formatSuggestion(allocator, "pritn", "print");
    defer allocator.free(msg);

    try std.testing.expectEqualStrings("Did you mean 'print'?", msg);
}

test "format name error" {
    const allocator = std.testing.allocator;

    const msg1 = try formatNameError(allocator, "foo", "for");
    defer allocator.free(msg1);
    try std.testing.expect(std.mem.indexOf(u8, msg1, "Did you mean") != null);

    const msg2 = try formatNameError(allocator, "xyz", null);
    defer allocator.free(msg2);
    try std.testing.expect(std.mem.indexOf(u8, msg2, "Did you mean") == null);
}
