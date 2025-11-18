//! Comptime type inference helpers for PyAOT
//! These functions run at Zig compile time to infer optimal types

const std = @import("std");

/// Check if a type is a string literal (*const [N:0]u8)
fn isStringLiteral(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const ptr = info.pointer;
        if (ptr.size == .one and ptr.is_const) {
            const child_info = @typeInfo(ptr.child);
            if (child_info == .array) {
                return child_info.array.child == u8 and child_info.array.sentinel_ptr != null;
            }
        }
    }
    return false;
}

/// Infer the best ArrayList element type from a comptime-known tuple of values
/// Follows Python's type promotion hierarchy: int < float < string
pub fn InferListType(comptime TupleType: type) type {
    const type_info = @typeInfo(TupleType);

    // Must be a tuple (anonymous struct)
    if (type_info != .@"struct") {
        @compileError("InferListType expects a tuple type");
    }

    const fields = type_info.@"struct".fields;
    if (fields.len == 0) {
        return i64; // Default empty list type
    }

    // Type promotion: start with narrowest, widen as needed
    comptime var result_type: type = i64;
    comptime var has_float = false;
    comptime var has_string = false;

    inline for (fields) |field| {
        const T = field.type;

        // Check for float types (including comptime_float!)
        if (T == f64 or T == f32 or T == f16 or T == comptime_float) {
            has_float = true;
        }
        // Check for string types (both slices and string literals)
        else if (T == []const u8 or T == []u8) {
            has_string = true;
        }
        // Check for string literals (*const [N:0]u8)
        else if (@typeInfo(T) == .pointer) {
            const ptr_info = @typeInfo(T).pointer;
            if (ptr_info.size == .one) {
                // Check if it points to a sentinel-terminated array of u8
                if (@typeInfo(ptr_info.child) == .array) {
                    const array_info = @typeInfo(ptr_info.child).array;
                    if (array_info.child == u8 and array_info.sentinel_ptr != null) {
                        has_string = true;
                    }
                }
            }
        }
    }

    // Type promotion hierarchy
    if (has_string) {
        result_type = []const u8; // String is most general
    } else if (has_float) {
        result_type = f64; // Float can hold integers
    } else {
        result_type = i64; // All integers
    }

    return result_type;
}

/// Create an ArrayList from a comptime-known tuple with automatic type inference
/// This runs at Zig compile time and generates optimal code
pub fn createListComptime(comptime values: anytype, allocator: std.mem.Allocator) !std.ArrayList(InferListType(@TypeOf(values))) {
    const T = comptime InferListType(@TypeOf(values));
    var list = std.ArrayList(T){};

    // Inline loop - unrolled at compile time for maximum performance
    inline for (values) |val| {
        // Auto-cast if needed
        const cast_val = if (@TypeOf(val) != T) blk: {
            // int → float conversion
            if (T == f64 and (@TypeOf(val) == i64 or @TypeOf(val) == comptime_int)) {
                break :blk @as(f64, @floatFromInt(val));
            }
            // TODO: Add string conversion when T == []const u8
            break :blk val;
        } else val;

        try list.append(allocator, cast_val);
    }

    return list;
}

/// Infer type for a single value at comptime
pub fn InferValueType(comptime ValueType: type) type {
    return switch (ValueType) {
        i64, i32, i16, i8, comptime_int => i64,
        f64, f32, f16, comptime_float => f64,
        []const u8, []u8 => []const u8,
        bool => bool,
        else => ValueType, // Pass through
    };
}

/// Check if a type can be widened to another type
pub fn canWiden(comptime From: type, comptime To: type) bool {
    // int → float
    if ((From == i64 or From == comptime_int) and To == f64) return true;

    // Anything → string (via str())
    if (To == []const u8) return true;

    // Same type
    if (From == To) return true;

    return false;
}

/// Infer dict value type from comptime-known key-value pairs
/// Assumes keys are strings, infers value type with widening
pub fn InferDictValueType(comptime TupleType: type) type {
    const type_info = @typeInfo(TupleType);

    if (type_info != .@"struct") {
        @compileError("InferDictValueType expects a tuple type");
    }

    const fields = type_info.@"struct".fields;
    if (fields.len == 0) {
        return i64; // Default empty dict value type
    }

    // Each field should be a 2-tuple (key, value)
    // We only care about value types (index 1)
    comptime var result_type: type = i64;
    comptime var has_float = false;
    comptime var has_string = false;

    inline for (fields) |field| {
        const KV = field.type;
        const kv_info = @typeInfo(KV);

        if (kv_info != .@"struct") continue;
        const kv_fields = kv_info.@"struct".fields;
        if (kv_fields.len != 2) continue;

        const V = kv_fields[1].type; // Value type

        // Check value type
        if (V == f64 or V == f32 or V == f16 or V == comptime_float) {
            has_float = true;
        } else if (V == []const u8 or V == []u8 or isStringLiteral(V)) {
            has_string = true;
        }
    }

    // Type promotion hierarchy
    if (has_string) {
        result_type = []const u8;
    } else if (has_float) {
        result_type = f64;
    } else {
        result_type = i64;
    }

    return result_type;
}

test "InferListType - homogeneous int" {
    const T = InferListType(@TypeOf(.{ 1, 2, 3 }));
    try std.testing.expectEqual(i64, T);
}

test "InferListType - mixed int and float" {
    const T = InferListType(@TypeOf(.{ 1, 2.5, 3 }));
    try std.testing.expectEqual(f64, T);
}

test "InferListType - with string" {
    const T = InferListType(@TypeOf(.{ 1, "hello" }));
    try std.testing.expectEqual([]const u8, T);
}

test "createListComptime - int to float widening" {
    const allocator = std.testing.allocator;

    var list = try createListComptime(.{ 1, 2.5, 3 }, allocator);
    defer list.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(f64, 1.0), list.items[0]);
    try std.testing.expectEqual(@as(f64, 2.5), list.items[1]);
    try std.testing.expectEqual(@as(f64, 3.0), list.items[2]);
}
