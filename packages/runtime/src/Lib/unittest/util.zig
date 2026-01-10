//! unittest.util - Utility functions for unittest
//! Reference: cpython/Lib/unittest/util.py
//!
//! CPython __all__: ['strclass', 'safe_repr', 'sorted_list_difference',
//!                   'unorderable_list_difference', 'three_way_cmp']
//!
//! Provides utility functions used by unittest internals.

const std = @import("std");

// ============================================================================
// String Utilities
// ============================================================================

/// CPython: def strclass(cls)
/// Return the class name prefixed with the module name.
/// Format: "module.ClassName"
pub fn strclass(class_name: []const u8, module_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, class_name });
}

/// CPython: def safe_repr(obj, short=False)
/// Return a string representation, catching exceptions.
/// Limits output length to avoid huge outputs.
pub fn safe_repr(obj: anytype, short: bool, allocator: std.mem.Allocator) ![]u8 {
    const max_len: usize = if (short) 80 else 80 * 8;

    // Try to get a string representation
    const repr = blk: {
        const T = @TypeOf(obj);
        if (comptime std.meta.trait.hasMethod(T, "format")) {
            var buf: [4096]u8 = undefined;
            const len = std.fmt.formatBuf(&buf, "{any}", .{obj}) catch break :blk "<error in repr>";
            break :blk buf[0..len];
        }
        break :blk "<object>";
    };

    // Truncate if necessary
    if (repr.len > max_len) {
        const truncated = repr[0..max_len];
        return std.fmt.allocPrint(allocator, "{s} [truncated]...", .{truncated});
    }

    return allocator.dupe(u8, repr);
}

/// Simplified safe_repr that returns a static string representation
pub fn safeReprStatic(obj: anytype) []const u8 {
    const T = @TypeOf(obj);
    if (T == []const u8 or T == []u8) {
        return obj;
    }
    if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return "<int>";
    }
    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        return "<float>";
    }
    if (@typeInfo(T) == .bool) {
        return if (obj) "True" else "False";
    }
    return "<object>";
}

// ============================================================================
// List Comparison Utilities
// ============================================================================

/// CPython: def sorted_list_difference(expected, actual)
/// Return a sorted list of (expected_only, actual_only) differences.
/// Both lists must be sortable.
pub fn sorted_list_difference(
    comptime T: type,
    expected: []const T,
    actual: []const T,
    allocator: std.mem.Allocator,
) !struct {
    expected_only: std.ArrayList(T),
    actual_only: std.ArrayList(T),
} {
    var expected_only = std.ArrayList(T).init(allocator);
    var actual_only = std.ArrayList(T).init(allocator);

    // Find items in expected but not in actual
    for (expected) |item| {
        var found = false;
        for (actual) |a| {
            if (std.meta.eql(item, a)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try expected_only.append(item);
        }
    }

    // Find items in actual but not in expected
    for (actual) |item| {
        var found = false;
        for (expected) |e| {
            if (std.meta.eql(item, e)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try actual_only.append(item);
        }
    }

    return .{
        .expected_only = expected_only,
        .actual_only = actual_only,
    };
}

/// CPython: def unorderable_list_difference(expected, actual)
/// Return (expected_only, actual_only) for unsortable items.
/// Uses a different algorithm that doesn't require sorting.
pub fn unorderable_list_difference(
    comptime T: type,
    expected: []const T,
    actual: []const T,
    allocator: std.mem.Allocator,
) !struct {
    expected_only: std.ArrayList(T),
    actual_only: std.ArrayList(T),
} {
    // Same implementation as sorted_list_difference for now
    return sorted_list_difference(T, expected, actual, allocator);
}

// ============================================================================
// Comparison Functions
// ============================================================================

/// CPython: def three_way_cmp(x, y)
/// Compare two values, returning -1, 0, or 1.
/// Used for sorting test methods.
pub fn three_way_cmp(x: []const u8, y: []const u8) std.math.Order {
    return std.mem.order(u8, x, y);
}

/// Compare function suitable for use with std.sort
pub fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// ============================================================================
// Diff Generation
// ============================================================================

/// Maximum number of diff lines to show
pub const MAX_DIFF_LINES: usize = 200;

/// Generate a unified diff between two strings
pub fn generateDiff(
    expected: []const u8,
    actual: []const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.print("--- expected\n", .{});
    try writer.print("+++ actual\n", .{});

    var exp_lines = std.mem.splitScalar(u8, expected, '\n');
    var act_lines = std.mem.splitScalar(u8, actual, '\n');

    var line_num: usize = 1;
    while (true) {
        const exp_line = exp_lines.next();
        const act_line = act_lines.next();

        if (exp_line == null and act_line == null) break;
        if (line_num > MAX_DIFF_LINES) {
            try writer.print("... (truncated, too many differences)\n", .{});
            break;
        }

        if (exp_line) |e| {
            if (act_line) |a| {
                if (!std.mem.eql(u8, e, a)) {
                    try writer.print("-{s}\n", .{e});
                    try writer.print("+{s}\n", .{a});
                } else {
                    try writer.print(" {s}\n", .{e});
                }
            } else {
                try writer.print("-{s}\n", .{e});
            }
        } else if (act_line) |a| {
            try writer.print("+{s}\n", .{a});
        }

        line_num += 1;
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Type Checking Utilities
// ============================================================================

/// Check if a value is a test function (starts with "test")
pub fn isTestMethod(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "test");
}

/// Check if a value is a test class (inherits from TestCase)
pub fn isTestClass(comptime T: type) bool {
    // In Zig, we can check for required methods
    return @hasDecl(T, "setUp") and @hasDecl(T, "tearDown");
}

// ============================================================================
// Assertion Message Formatting
// ============================================================================

/// Format an assertion error message
pub fn formatAssertionMessage(
    standard_msg: []const u8,
    custom_msg: ?[]const u8,
    allocator: std.mem.Allocator,
) ![]u8 {
    if (custom_msg) |msg| {
        return std.fmt.allocPrint(allocator, "{s} : {s}", .{ standard_msg, msg });
    }
    return allocator.dupe(u8, standard_msg);
}

/// Truncate a string for display
pub fn truncateForDisplay(s: []const u8, max_len: usize) []const u8 {
    if (s.len <= max_len) return s;
    return s[0..max_len];
}

// ============================================================================
// Tests
// ============================================================================

test "strclass" {
    const allocator = std.testing.allocator;
    const result = try strclass("MyClass", "my_module", allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("my_module.MyClass", result);
}

test "three_way_cmp" {
    try std.testing.expectEqual(std.math.Order.lt, three_way_cmp("aaa", "bbb"));
    try std.testing.expectEqual(std.math.Order.gt, three_way_cmp("bbb", "aaa"));
    try std.testing.expectEqual(std.math.Order.eq, three_way_cmp("aaa", "aaa"));
}

test "isTestMethod" {
    try std.testing.expect(isTestMethod("test_foo"));
    try std.testing.expect(isTestMethod("testBar"));
    try std.testing.expect(!isTestMethod("setUp"));
    try std.testing.expect(!isTestMethod("helper"));
}

test "sorted_list_difference" {
    const allocator = std.testing.allocator;
    const expected = [_]i32{ 1, 2, 3, 4 };
    const actual = [_]i32{ 2, 3, 5, 6 };

    var diff = try sorted_list_difference(i32, &expected, &actual, allocator);
    defer diff.expected_only.deinit();
    defer diff.actual_only.deinit();

    try std.testing.expectEqual(@as(usize, 2), diff.expected_only.items.len); // 1, 4
    try std.testing.expectEqual(@as(usize, 2), diff.actual_only.items.len); // 5, 6
}

test "truncateForDisplay" {
    const long_string = "This is a very long string that should be truncated";
    const result = truncateForDisplay(long_string, 20);
    try std.testing.expectEqual(@as(usize, 20), result.len);
}
