/// Dynamic value type for runtime attribute storage
/// Supports comptime SIMD operations for string comparisons
const std = @import("std");

/// PyValue - Runtime-typed value for dynamic attributes
/// Uses tagged union for type safety
pub const PyValue = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bool: bool,
    none: void,

    /// Format value for printing
    pub fn format(
        self: PyValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d}", .{v}),
            .string => |v| try writer.print("{s}", .{v}),
            .bool => |v| try writer.print("{}", .{v}),
            .none => try writer.writeAll("None"),
        }
    }

    /// Convert to integer (if possible)
    pub fn toInt(self: PyValue) ?i64 {
        return switch (self) {
            .int => |v| v,
            .float => |v| @intFromFloat(v),
            .bool => |v| if (v) @as(i64, 1) else @as(i64, 0),
            else => null,
        };
    }

    /// Convert to float (if possible)
    pub fn toFloat(self: PyValue) ?f64 {
        return switch (self) {
            .float => |v| v,
            .int => |v| @floatFromInt(v),
            else => null,
        };
    }

    /// Check if value is truthy
    pub fn isTruthy(self: PyValue) bool {
        return switch (self) {
            .bool => |v| v,
            .int => |v| v != 0,
            .float => |v| v != 0.0,
            .string => |v| v.len > 0,
            .none => false,
        };
    }
};

/// Optimized string comparison using comptime SIMD if available
/// Falls back to std.mem.eql for smaller strings
pub fn eqlString(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len == 0) return true;

    // Use comptime to select best comparison method
    const use_simd = comptime blk: {
        // SIMD is beneficial for strings >= 16 bytes on most platforms
        const min_simd_len = 16;
        // Check if platform supports SIMD
        const has_simd = @import("builtin").cpu.arch.endian() == .little;
        break :blk has_simd and a.len >= min_simd_len;
    };

    if (use_simd) {
        // For longer strings, use vectorized comparison
        return simdEql(a, b);
    } else {
        // For short strings, use standard comparison
        return std.mem.eql(u8, a, b);
    }
}

/// SIMD-optimized string equality check
fn simdEql(a: []const u8, b: []const u8) bool {
    const len = a.len;

    // Process 16 bytes at a time using @Vector
    const vec_len = 16;
    const Vec = @Vector(vec_len, u8);

    var i: usize = 0;
    while (i + vec_len <= len) : (i += vec_len) {
        const va: Vec = a[i..][0..vec_len].*;
        const vb: Vec = b[i..][0..vec_len].*;

        // Compare vectors element-wise
        if (!@reduce(.And, va == vb)) {
            return false;
        }
    }

    // Handle remaining bytes
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }

    return true;
}

test "PyValue basic operations" {
    const testing = std.testing;

    const v_int = PyValue{ .int = 42 };
    const v_float = PyValue{ .float = 3.14 };
    const v_str = PyValue{ .string = "hello" };
    const v_bool = PyValue{ .bool = true };
    const v_none = PyValue{ .none = {} };

    try testing.expectEqual(@as(i64, 42), v_int.toInt().?);
    try testing.expectEqual(@as(f64, 3.14), v_float.toFloat().?);
    try testing.expect(v_bool.isTruthy());
    try testing.expect(!v_none.isTruthy());
}

test "SIMD string comparison" {
    const testing = std.testing;

    const str1 = "hello world from PyAOT compiler!";
    const str2 = "hello world from PyAOT compiler!";
    const str3 = "hello world from PyAOT compiler?";

    try testing.expect(eqlString(str1, str2));
    try testing.expect(!eqlString(str1, str3));
    try testing.expect(eqlString("", ""));
    try testing.expect(!eqlString("a", ""));
}
