//! Comptime type inference helpers for metal0
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

/// Check if a type is a tuple (anonymous struct with no named fields)
fn isTupleType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    const fields = info.@"struct".fields;
    if (fields.len == 0) return false;
    // Check if first field has a generated name (starts with digit)
    return fields[0].name[0] >= '0' and fields[0].name[0] <= '9';
}

/// Widen a single type position across multiple tuple elements
/// Returns ?T if any element has null/void at this position
fn widenTuplePosition(comptime T1: type, comptime T2: type) type {
    // Same types - no change needed
    if (T1 == T2) return T1;

    // Handle null (@TypeOf(null)) and void types - make optional
    if (T2 == @TypeOf(null) or T2 == void or T2 == ?void) {
        // T1 + null = ?T1
        if (@typeInfo(T1) == .optional) return T1; // Already optional
        return ?T1;
    }
    if (T1 == @TypeOf(null) or T1 == void or T1 == ?void) {
        // null + T2 = ?T2
        if (@typeInfo(T2) == .optional) return T2; // Already optional
        return ?T2;
    }

    // String literal + []const u8 = []const u8
    if (isStringLiteral(T1) and T2 == []const u8) return []const u8;
    if (isStringLiteral(T2) and T1 == []const u8) return []const u8;
    if (isStringLiteral(T1) and isStringLiteral(T2)) return []const u8;

    // Default: keep first type
    return T1;
}

/// Infer element type for a list of tuples with element-wise widening
fn InferTupleListType(comptime TupleType: type) type {
    const outer_info = @typeInfo(TupleType);
    const outer_fields = outer_info.@"struct".fields;
    if (outer_fields.len == 0) return struct {};

    // Get the first tuple to determine structure
    const FirstTuple = outer_fields[0].type;
    const first_info = @typeInfo(FirstTuple);
    if (first_info != .@"struct") return FirstTuple;

    const tuple_len = first_info.@"struct".fields.len;
    if (tuple_len == 0) return struct {};

    // Build widened tuple type by examining all tuples at each position
    comptime var widened_types: [tuple_len]type = undefined;

    inline for (0..tuple_len) |pos_idx| {
        // Start with first tuple's type at this position
        comptime var pos_type: type = first_info.@"struct".fields[pos_idx].type;

        // Widen with remaining tuples
        inline for (outer_fields[1..]) |outer_field| {
            const inner_info = @typeInfo(outer_field.type);
            if (inner_info == .@"struct" and inner_info.@"struct".fields.len > pos_idx) {
                pos_type = widenTuplePosition(pos_type, inner_info.@"struct".fields[pos_idx].type);
            }
        }

        // Normalize string literals to []const u8
        if (isStringLiteral(pos_type)) {
            pos_type = []const u8;
        } else if (@typeInfo(pos_type) == .optional) {
            const child = @typeInfo(pos_type).optional.child;
            if (isStringLiteral(child)) {
                pos_type = ?[]const u8;
            }
        }

        widened_types[pos_idx] = pos_type;
    }

    // Generate the struct type
    comptime var struct_fields: [tuple_len]std.builtin.Type.StructField = undefined;
    inline for (0..tuple_len) |i| {
        struct_fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = widened_types[i],
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &struct_fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Infer the best ArrayList element type from a comptime-known tuple of values
/// Follows Python's type promotion hierarchy: int < float < string
/// For lists of tuples, performs element-wise widening across all positions
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

    // Check if first element is a tuple - if so, do element-wise widening
    if (isTupleType(fields[0].type)) {
        return InferTupleListType(TupleType);
    }

    // Type promotion: start with narrowest, widen as needed
    comptime var has_int = false;
    comptime var has_float = false;
    comptime var has_string = false;
    comptime var has_other = false; // ArrayList, PyValue, etc.
    comptime var other_type: ?type = null; // Track the "other" type if all are same
    comptime var all_other_same = true; // Are all "other" types identical?
    // Track array element types for arrays of different lengths
    comptime var all_arrays = true;
    comptime var array_child_type: ?type = null;
    comptime var array_child_same = true;

    inline for (fields) |field| {
        const T = field.type;

        // Check for int types
        if (T == i64 or T == i32 or T == comptime_int or T == usize or T == isize) {
            has_int = true;
            all_arrays = false;
        }
        // Check for float types (including comptime_float!)
        else if (T == f64 or T == f32 or T == f16 or T == comptime_float) {
            has_float = true;
            all_arrays = false;
        }
        // Check for string types (both slices and string literals)
        else if (T == []const u8 or T == []u8) {
            has_string = true;
            all_arrays = false;
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
                        all_arrays = false;
                    } else {
                        has_other = true;
                        all_arrays = false;
                        if (other_type == null) {
                            other_type = T;
                        } else if (other_type != T) {
                            all_other_same = false;
                        }
                    }
                } else {
                    has_other = true;
                    all_arrays = false;
                    if (other_type == null) {
                        other_type = T;
                    } else if (other_type != T) {
                        all_other_same = false;
                    }
                }
            } else {
                has_other = true;
                all_arrays = false;
                if (other_type == null) {
                    other_type = T;
                } else if (other_type != T) {
                    all_other_same = false;
                }
            }
        }
        // Check for PyValue
        else if (T == @import("py_value.zig").PyValue) {
            // PyValue stays as PyValue
            has_other = true;
            all_arrays = false;
            if (other_type == null) {
                other_type = T;
            } else if (other_type != T) {
                all_other_same = false;
            }
        }
        // Check for arrays [N]T - track child type for arrays of different sizes
        else if (@typeInfo(T) == .array) {
            const arr_info = @typeInfo(T).array;
            has_other = true;
            if (other_type == null) {
                other_type = T;
            } else if (other_type != T) {
                all_other_same = false;
            }
            // Track array child type for slice conversion
            if (array_child_type == null) {
                array_child_type = arr_info.child;
            } else if (array_child_type != arr_info.child) {
                array_child_same = false;
            }
        }
        // Other types (ArrayList, custom structs, etc.)
        else {
            has_other = true;
            all_arrays = false;
            if (other_type == null) {
                other_type = T;
            } else if (other_type != T) {
                all_other_same = false;
            }
        }
    }

    // Type promotion hierarchy - if mixed incompatible types, use PyValue
    const num_categories = @as(u8, if (has_int or has_float) 1 else 0) +
        @as(u8, if (has_string) 1 else 0) +
        @as(u8, if (has_other) 1 else 0);

    if (num_categories > 1) {
        // Mixed types (e.g., int + ArrayList) - use PyValue
        return @import("py_value.zig").PyValue;
    } else if (has_other) {
        // Only "other" types - check if all same
        if (all_other_same and other_type != null) {
            return other_type.?;
        }
        // Check if all are arrays with same child type but different sizes
        // In this case, use slice []child instead of [N]child
        if (all_arrays and array_child_same and array_child_type != null) {
            return []const array_child_type.?;
        }
        // Heterogeneous "other" types - use PyValue
        return @import("py_value.zig").PyValue;
    } else if (has_string) {
        return []const u8;
    } else if (has_float) {
        return f64;
    } else {
        return i64;
    }
}

/// Create an ArrayList from a comptime-known tuple with automatic type inference
/// This runs at Zig compile time and generates optimal code
pub fn createListComptime(comptime values: anytype, allocator: std.mem.Allocator) !std.ArrayList(InferListType(@TypeOf(values))) {
    const PyValue = @import("py_value.zig").PyValue;
    const T = comptime InferListType(@TypeOf(values));
    var list = std.ArrayList(T){};

    // Inline loop - unrolled at compile time for maximum performance
    inline for (values) |val| {
        // Auto-cast if needed
        const cast_val = if (@TypeOf(val) != T) blk: {
            // PyValue conversion for heterogeneous lists
            if (T == PyValue) {
                break :blk try PyValue.fromAlloc(allocator, val);
            }
            // int → float conversion
            if (T == f64 and (@TypeOf(val) == i64 or @TypeOf(val) == comptime_int)) {
                break :blk @as(f64, @floatFromInt(val));
            }
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
