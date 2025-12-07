//! CPython source: Lib/copy.py
//!
//! Provides generic shallow and deep copying operations.
//! Deep copy creates a new compound object and recursively copies all objects found.
//!
//! Mirrors: CPython Lib/copy.py

const std = @import("std");

pub const CopyError = error{
    OutOfMemory,
    UnsupportedType,
    CircularReference,
};

/// Create a shallow copy of an object
/// For primitive types, returns the value directly.
/// For slices/arrays, copies the slice (not the underlying data).
pub fn copy(value: anytype) @TypeOf(value) {
    return value;
}

/// Create a deep copy of an object
/// Recursively copies all nested structures
pub fn deepcopy(allocator: std.mem.Allocator, value: anytype) !DeepCopyResult(@TypeOf(value)) {
    return deepcopyImpl(allocator, value);
}

fn DeepCopyResult(comptime T: type) type {
    const info = @typeInfo(T);
    return switch (info) {
        .pointer => |ptr| if (ptr.size == .Slice)
            []ptr.child
        else
            T,
        .array => |arr| []arr.child,
        else => T,
    };
}

fn deepcopyImpl(allocator: std.mem.Allocator, value: anytype) !DeepCopyResult(@TypeOf(value)) {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        // Primitive types - just return the value
        .int, .float, .bool, .void, .null, .undefined, .noreturn, .comptime_int, .comptime_float => {
            return value;
        },

        // Enums - return as-is
        .@"enum" => {
            return value;
        },

        // Optional - recursively copy if present
        .optional => {
            if (value) |v| {
                return try deepcopyImpl(allocator, v);
            }
            return null;
        },

        // Pointers - need to handle slices specially
        .pointer => |ptr| {
            if (ptr.size == .Slice) {
                // Deep copy each element of the slice
                const result = try allocator.alloc(ptr.child, value.len);
                errdefer allocator.free(result);

                for (value, 0..) |elem, i| {
                    result[i] = try deepcopyImpl(allocator, elem);
                }
                return result;
            } else {
                // Single pointer - just return (can't deep copy without knowing ownership)
                return value;
            }
        },

        // Arrays - convert to owned slice
        .array => |arr| {
            const result = try allocator.alloc(arr.child, arr.len);
            errdefer allocator.free(result);

            for (value, 0..) |elem, i| {
                result[i] = try deepcopyImpl(allocator, elem);
            }
            return result;
        },

        // Structs - copy field by field
        .@"struct" => |s| {
            var result: T = undefined;
            inline for (s.fields) |field| {
                @field(result, field.name) = try deepcopyImpl(allocator, @field(value, field.name));
            }
            return result;
        },

        // Unions - copy the active field
        .@"union" => |u| {
            if (u.tag_type) |_| {
                // Tagged union
                const tag = std.meta.activeTag(value);
                inline for (u.fields) |field| {
                    if (tag == @field(std.meta.Tag(T), field.name)) {
                        const field_value = @field(value, field.name);
                        return @unionInit(T, field.name, try deepcopyImpl(allocator, field_value));
                    }
                }
            }
            // Untagged union - can't safely copy
            return value;
        },

        else => {
            // Unsupported types - return as-is
            return value;
        },
    }
}

/// Replace an object in-place with a copy
pub fn replace(dest: anytype, src: @TypeOf(dest.*)) void {
    dest.* = src;
}

/// Error types for copy operations
pub const Error = error{
    /// The object is not copyable
    NotCopyable,
    /// Circular reference detected during deep copy
    CircularReference,
    /// Out of memory
    OutOfMemory,
};

// ============================================================================
// Memo for tracking copied objects (prevents circular references)
// ============================================================================

pub fn CopyMemo(comptime KeyType: type, comptime ValueType: type) type {
    return struct {
        map: std.AutoHashMap(KeyType, ValueType),

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = std.AutoHashMap(KeyType, ValueType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit();
        }

        pub fn get(self: *Self, key: KeyType) ?ValueType {
            return self.map.get(key);
        }

        pub fn put(self: *Self, key: KeyType, value: ValueType) !void {
            try self.map.put(key, value);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "copy primitives" {
    try std.testing.expectEqual(@as(i32, 42), copy(@as(i32, 42)));
    try std.testing.expectEqual(@as(f64, 3.14), copy(@as(f64, 3.14)));
    try std.testing.expectEqual(true, copy(true));
}

test "deepcopy primitives" {
    const allocator = std.testing.allocator;

    const i = try deepcopy(allocator, @as(i32, 42));
    try std.testing.expectEqual(@as(i32, 42), i);

    const f = try deepcopy(allocator, @as(f64, 3.14));
    try std.testing.expectEqual(@as(f64, 3.14), f);
}

test "deepcopy slice" {
    const allocator = std.testing.allocator;

    const original = [_]i32{ 1, 2, 3, 4, 5 };
    const copied = try deepcopy(allocator, @as([]const i32, &original));
    defer allocator.free(copied);

    try std.testing.expectEqual(@as(usize, 5), copied.len);
    try std.testing.expectEqual(@as(i32, 1), copied[0]);
    try std.testing.expectEqual(@as(i32, 5), copied[4]);

    // Verify it's a true copy (different memory)
    try std.testing.expect(@intFromPtr(copied.ptr) != @intFromPtr(&original));
}

test "deepcopy array" {
    const allocator = std.testing.allocator;

    const original = [_]i32{ 10, 20, 30 };
    const copied = try deepcopy(allocator, original);
    defer allocator.free(copied);

    try std.testing.expectEqual(@as(usize, 3), copied.len);
    try std.testing.expectEqual(@as(i32, 10), copied[0]);
    try std.testing.expectEqual(@as(i32, 30), copied[2]);
}

test "deepcopy struct" {
    const allocator = std.testing.allocator;

    const Point = struct {
        x: i32,
        y: i32,
    };

    const original = Point{ .x = 10, .y = 20 };
    const copied = try deepcopy(allocator, original);

    try std.testing.expectEqual(@as(i32, 10), copied.x);
    try std.testing.expectEqual(@as(i32, 20), copied.y);
}

test "deepcopy optional" {
    const allocator = std.testing.allocator;

    const some: ?i32 = 42;
    const none: ?i32 = null;

    const copied_some = try deepcopy(allocator, some);
    const copied_none = try deepcopy(allocator, none);

    try std.testing.expectEqual(@as(?i32, 42), copied_some);
    try std.testing.expectEqual(@as(?i32, null), copied_none);
}

test "CopyMemo" {
    const allocator = std.testing.allocator;
    var memo = CopyMemo(usize, usize).init(allocator);
    defer memo.deinit();

    try memo.put(1, 100);
    try memo.put(2, 200);

    try std.testing.expectEqual(@as(?usize, 100), memo.get(1));
    try std.testing.expectEqual(@as(?usize, 200), memo.get(2));
    try std.testing.expectEqual(@as(?usize, null), memo.get(3));
}
