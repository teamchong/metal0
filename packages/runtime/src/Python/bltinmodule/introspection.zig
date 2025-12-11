/// introspection - Object Introspection Functions
/// type(), hash(), id(), repr(), ascii() implementations.

const std = @import("std");
const errors = @import("../errors.zig");

// ============================================================================
// Object Introspection
// ============================================================================

/// Get type name of object
/// Mirrors: builtin type()
pub fn type_builtin(comptime T: type) []const u8 {
    return @typeName(T);
}

/// Get hash of object
/// Mirrors: builtin hash()
pub fn hash_builtin(value: anytype) u64 {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int, .comptime_int => @bitCast(@as(i64, value)),
        .float => @bitCast(value),
        .bool => if (value) 1 else 0,
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                // String hash using FNV-1a
                var h: u64 = 14695981039346656037;
                for (value) |byte| {
                    h ^= byte;
                    h *%= 1099511628211;
                }
                return h;
            }
            return @intFromPtr(value);
        },
        else => @intFromPtr(&value),
    };
}

/// Get unique ID of object
/// Mirrors: builtin id()
pub fn id_builtin(value: anytype) usize {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => @intFromPtr(value),
        else => @intFromPtr(&value),
    };
}

/// Get repr of object
/// Mirrors: builtin repr()
pub fn repr_builtin(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);

    return switch (@typeInfo(T)) {
        .int, .comptime_int => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .float, .comptime_float => std.fmt.allocPrint(allocator, "{d}", .{value}),
        .bool => if (value) "True" else "False",
        .pointer => |ptr_info| {
            if (ptr_info.child == u8) {
                // String repr with quotes
                return std.fmt.allocPrint(allocator, "'{s}'", .{value});
            }
            return std.fmt.allocPrint(allocator, "<{s} at {*}>", .{ @typeName(T), value });
        },
        else => std.fmt.allocPrint(allocator, "<{s}>", .{@typeName(T)}),
    };
}

/// Get ASCII representation
/// Mirrors: builtin ascii()
pub fn ascii_builtin(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    try result.append(allocator, '\'');

    for (value) |byte| {
        if (byte >= 0x20 and byte < 0x7f and byte != '\'' and byte != '\\') {
            try result.append(allocator, byte);
        } else if (byte == '\\') {
            try result.appendSlice(allocator, "\\\\");
        } else if (byte == '\'') {
            try result.appendSlice(allocator, "\\'");
        } else if (byte == '\n') {
            try result.appendSlice(allocator, "\\n");
        } else if (byte == '\r') {
            try result.appendSlice(allocator, "\\r");
        } else if (byte == '\t') {
            try result.appendSlice(allocator, "\\t");
        } else {
            try result.writer(allocator).print("\\x{x:0>2}", .{byte});
        }
    }

    try result.append(allocator, '\'');
    return result.toOwnedSlice(allocator);
}

/// Check if object is callable
/// Mirrors: builtin callable()
pub fn callable_builtin(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"fn", .bound_fn => true,
        .pointer => |ptr_info| {
            return @typeInfo(ptr_info.child) == .@"fn";
        },
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "hash function" {
    const h1 = hash_builtin("hello");
    const h2 = hash_builtin("hello");
    const h3 = hash_builtin("world");

    try std.testing.expectEqual(h1, h2);
    try std.testing.expect(h1 != h3);
}
